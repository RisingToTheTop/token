const { update, resolve } = require('dnslink');

const uploadDnsLink = async () => {
  await update('wagmitest.io', '/ipfs/QmStyTZJJugmdFub1GBBGhtXpwxghT4EGvBCz8jNSLdBcy');
  // update('wagmitest.io', '/ipfs/20011229')
  // .then((res) => {console.log("saved!", res)});
}

const main = async () => {
  await uploadDnsLink();
  console.log("finished!");
}

main();