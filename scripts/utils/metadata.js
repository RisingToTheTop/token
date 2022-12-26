// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

const request = require('request');
const Moralis = require("moralis-v1/node");
const fs = require("fs");
const { default: axios } = require("axios");
const { editionSize, assetElement } = require("../../assets/config.js");

// const serverUrl = process.env.MORALIS_SERVER_URL;
// const appId = process.env.MORALIS_APPLICATION_ID;
// const masterKey = process.env.MASTER_KEY;
// const apiUrl = process.env.API_URL;
// const apiKey = process.env.API_KEY;

const serverUrl = "https://wagmi-music.herokuapp.com/server";
const appId = "001";
const masterKey = "123";
const apiUrl = "https://deep-index.moralis.io/api/v2/ipfs/uploadFolder";
const apiKey = "Xe3Rkn1tkm7dc83ElaTUbsNNtdcYR2Gi5jrmrSsUbdxL4DYr5EHo8ZNXpaPEDXie";

Moralis.start({ serverUrl, appId, masterKey});

const btoa = (text) => {
  return Buffer.from(text, "binary").toString("base64");
}

// ローカルにmetadataを書き込み
const writeMetaData = (metadata) => {
  fs.writeFileSync("./output/_metadata.json", JSON.stringify(metadata));
};

// モラリスにアップロード
const saveToDb = async (metaHash) => {
  for(let i = 1; i <= editionSize; i++){
    let id = i.toString();
    let url = `https://ipfs.moralis.io:2053/ipfs/${metaHash}/metadata/${id}`;
    let options = { json: true };
  
    request(url, options, (error, res, body) => {
      if (error) {
        return console.log(error);
      }
  
      if (!error && res.statusCode == 200) {
        // moralisのダッシュボードにセーブ
        const FileDatabase = new Moralis.Object("Metadata");
        FileDatabase.set("name", body.name);
        FileDatabase.set("description", body.description);
        FileDatabase.set("image", body.image);
        FileDatabase.set("attributes", body.animation_url);
        FileDatabase.set("meta_hash", metaHash);
        FileDatabase.save();
      }
    });
    console.log(`${i}/${editionSize} have been saved for moralis dashboard`)
  }
};

const uploadImage = async () => {
  const UrlArray = [];

  for (let i = 0; i < editionSize; i++) {
    let id = i.toString();
    let image_base64, music_base64, ifiletype, mfiletype;
    image_base64 = music_base64 = null;

    if(assetElement[i].url){
      UrlArray.push({
        imageURL:"imageURL_NULL", 
        musicURL:"musicURL_NULL"
      });
      continue;
    }

    // データをIPFSにアップロード
    if(fs.existsSync(`./assets/jackets/${id}.jpeg`)){
      image_base64 = await btoa(fs.readFileSync(`./assets/jackets/${id}.jpeg`));
      ifiletype = "jpeg";
    } else if(fs.existsSync(`./assets/jackets/${id}.png`)) {
      image_base64 = await btoa(fs.readFileSync(`./assets/jackets/${id}.png`, (err,data) => {
        console.log(err)
      }));
      ifiletype = "png";
    } else if(fs.existsSync(`./assets/jackets/${id}.gif`)) {
      image_base64 = await btoa(fs.readFileSync(`./assets/jackets/${id}.gif`, (err,data) => {
        console.log(err)
      }));
      ifiletype = "gif";
    } else {
      console.log("jackets are not exist.")
    }

    if(fs.existsSync(`./assets/sounds/${id}.mp3`)){
      music_base64 = await btoa(fs.readFileSync(`./assets/sounds/${id}.mp3`));
      mfiletype = "mp3";
    } else if(fs.existsSync(`./assets/sounds/${id}.wav`)){
      music_base64 = await btoa(fs.readFileSync(`./assets/sounds/${id}.wav`));
      mfiletype = "wav";
    } else {
      console.log("sounds are not exist.")
    }
    let image_file = new Moralis.File("image.png", { base64: `data:image/${ifiletype};base64,${image_base64}` });
    let music_file = new Moralis.File("music.mp3", { base64: `data:audio/${mfiletype};base64,${music_base64}` });
    await image_file.saveIPFS({ useMasterKey: true });
    await music_file.saveIPFS({ useMasterKey: true });
    console.log(`Processing ${i}/${editionSize}...`)
    console.log("IPFS address of Image: ", image_file.ipfs());
    console.log("IPFS address of Music: ", music_file.ipfs());
    
    UrlArray.push({
      imageURL:image_file.ipfs(), 
      musicURL:music_file.ipfs()
    })
  }

  console.log(UrlArray)
  return UrlArray
}

const createMetadata = async () => {

  const metaDataArray = [];
  const DataArray  = await uploadImage();

  for (let i = 0; i < editionSize; i++){
    let id = (i+1).toString()
    let metadata;

    if(assetElement[i].url){
      try {
        const res = await axios.get(assetElement[i].url);
        metadata = res.data;
      } catch (error) {
        const {
          status,
          statusText
        } = error.response;
        console.log(`Error! HTTP Status: ${status} ${statusText}`);
      }
    }else{
      let imageURL = DataArray[i].imageURL
      let musicURL = DataArray[i].musicURL
    
      // メタデータを記述
      metadata = {
        "name": assetElement[i].name,
        "description": assetElement[i].description,
        "image": imageURL,
        "animation_url": musicURL,
        "attributes": assetElement[i].attributes
      }
    }
    
    metaDataArray.push(metadata);
  
    fs.writeFileSync(
      `./output/${id}.json`,
      JSON.stringify(metadata)
    );
  }
  writeMetaData(metaDataArray);
}

const uploadMetadata = async () => {
  const promiseArray = [];
  const ipfsArray = [];

  for(let i = 1; i <= editionSize; i++){
    let id = i.toString();
  
    // jsonファイルをipfsArrayにpush
    promiseArray.push(
      new Promise((res, rej) => {
        fs.readFile(`./output/${id}.json`, (err, data) => {
          if (err) rej();
          ipfsArray.push({
            path: `metadata/${id}`,
            content: data.toString("base64")
          });
          res();
        });
      })
    );
  }

  //プロミスが返ってきたらipfsArrayをapiにpost
  Promise.all(promiseArray).then(() => {
  axios
    .post(apiUrl, ipfsArray, {
      headers: {
        "X-API-Key": apiKey,
        "content-type": "application/json",
        accept: "application/json"
      }
    })
    .then(res => {
      let metaCID = res.data[0].path.split("/")[4];
      console.log("META FILE PATHS:", res.data);
      //モラリスにアップロード
      saveToDb(metaCID);
      console.log("all saved")
    })
    .catch(err => {
      console.log(err);
    });
  });
};

const startCreating = async () => {
  await createMetadata();
  await uploadMetadata();
  console.log("All finished!")
};

startCreating();
