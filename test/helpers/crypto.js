const EthJsUtil = require("ethereumjs-util");

export function recoverPublic(account) {
  // sign message
  const msg = new Buffer('hello');
  const sig = web3.eth.sign(account, '0x' + msg.toString('hex'));
  const res = EthJsUtil.fromRpcSig(sig);

  // ...and recover public from the signature
  const prefix = new Buffer("\x19Ethereum Signed Message:\n");
  const prefixedMsg = EthJsUtil.sha3(Buffer.concat([prefix, new Buffer(String(msg.length)), msg]));
  const pub = EthJsUtil.bufferToHex(EthJsUtil.ecrecover(prefixedMsg, res.v, res.r, res.s));

  return pub;
}