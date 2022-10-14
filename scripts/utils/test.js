const request = require('request');
const { editionSize, assetElement } = require("../../assets/config.js");

const testFunction = async () => {
  await request.get(assetElement[4].url, (err, res, body) => {
    if (err) {
      console.log('Error: ' + err.message);
      return;
    }
    console.log(body);
  })
}

const main = async () => {
  await testFunction();
}

main();