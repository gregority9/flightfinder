// Explicit manual integration check; not a mandatory CI dependency on Google uptime.
import fs from 'node:fs';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
const c=vm.createContext({});vm.runInContext(fs.readFileSync('ios/FlightDeck/Engine/fli-engine.js','utf8'),c);
const call=(name,...args)=>{const r=JSON.parse(c.FlightEngine[name](...args));if(r.error)throw Error(r.error);return r.data;};
const day=n=>new Date(Date.now()+n*86400000).toISOString().slice(0,10);
const query=JSON.stringify({origin:'GDN',destination:'HAM',departureDate:day(30),returnDate:day(34),adults:1,currency:'PLN',maxStops:1,cabin:'ECONOMY'});
const headers=['--max-time','35','--silent','--show-error','--fail','-A','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36','-H','Cookie: SOCS=CAISNQgQEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjQwMzE3LjA5X3AwGgJlbiADGgYIgLC_rwY'];
const page=url=>execFileSync('curl',[...headers,url],{encoding:'utf8',maxBuffer:12000000});
const out=call('decodePage',query,page(call('request',query).url)).rows;
if(!out.length)throw Error('No outbound results in manual smoke test');
const back=call('decodePage',query,page(call('request',query,out[0].wire).url)).rows;
if(!back.length)throw Error('No return results in manual smoke test');
const offer=call('offer',query,JSON.stringify([out[0].wire,back[0].wire]));
console.log(JSON.stringify({outboundRows:out.length,returnRows:back.length,price:offer.price,currency:offer.currency,journeys:offer.journeys},null,2));
