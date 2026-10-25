// Minimal web primitives required by Fli's pure codecs. No eval, browser, or network.
if (typeof globalThis.TextEncoder === 'undefined') globalThis.TextEncoder = class {
  encode(text='') { return Uint8Array.from(unescape(encodeURIComponent(text)), c=>c.charCodeAt(0)); }
};
if (typeof globalThis.TextDecoder === 'undefined') globalThis.TextDecoder = class {
  decode(bytes=new Uint8Array()) {
    const raw=Array.from(bytes,b=>String.fromCharCode(b)).join('');
    try { return decodeURIComponent(escape(raw)); } catch { return raw; }
  }
};
if (typeof globalThis.btoa === 'undefined') globalThis.btoa = function(s) {
  const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'; let out='';
  for(let i=0;i<s.length;i+=3) {
    const a=s.charCodeAt(i), b=s.charCodeAt(i+1), c=s.charCodeAt(i+2);
    out+=chars[a>>2]+chars[((a&3)<<4)|(Number.isNaN(b)?0:b>>4)]+(Number.isNaN(b)?'=':chars[((b&15)<<2)|(Number.isNaN(c)?0:c>>6)])+(Number.isNaN(c)?'=':chars[c&63]);
  } return out;
};
if (typeof globalThis.atob === 'undefined') globalThis.atob = function(s) {
  const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'; let out='', acc=0, bits=0;
  for(const c of s.replace(/=+$/,'')) { const v=chars.indexOf(c); if(v<0)throw Error('Invalid base64'); acc=(acc<<6)|v; bits+=6; if(bits>=8){bits-=8;out+=String.fromCharCode((acc>>bits)&255);} }
  return out;
};
