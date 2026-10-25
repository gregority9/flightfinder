import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
// Match a bare JavaScriptCore runtime: no fetch, Buffer, URL or browser primitives.
const context=vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../../ios/FlightDeck/Engine/fli-engine.js',import.meta.url),'utf8'),context);
const e=context.FlightEngine;
const day=n=>new Date(Date.now()+n*86400000).toISOString().slice(0,10);
const q={origin:'JFK',destination:'LHR',departureDate:day(30),adults:1,currency:'PLN',maxStops:0,cabin:'ECONOMY'};
const query=JSON.stringify(q);
const page=fs.readFileSync(new URL('./search-page.html',import.meta.url),'utf8');
const result=(method,...args)=>{const r=JSON.parse(e[method](...args));if(r.error)throw Error(r.error);return r.data;};

test('encodes searches without Node or browser globals',()=>{
  const url=result('request',query).url;
  assert.match(url,/^https:\/\/www.google.com\/travel\/flights\?tfs=/);
  assert.match(url,/curr=PLN/);
  assert.equal(typeof context.Buffer,'undefined');assert.equal(typeof context.fetch,'undefined');
});
test('real sanitized Google page decodes and keeps airport-local wall times',()=>{
  const rows=result('decodePage',query,page).rows;
  assert.ok(rows.length>0);
  const raw=JSON.parse(rows[0].wire);
  const offer=result('offer',query,JSON.stringify([rows[0].wire]));
  assert.equal(offer.journeys[0].legs[0].departure,raw.legs[0].departure_datetime);
  assert.equal(offer.journeys[0].legs[0].origin,'JFK');
  assert.match(offer.bookingUrl,/\/booking\?tfs=/);
});
test('return requests pin outbound and show selected return aggregate, never sum',()=>{
  const rows=result('decodePage',query,page).rows;
  const out=JSON.parse(rows[0].wire), back=structuredClone(out);
  out.price=400;out.currency='PLN';back.price=550;back.currency='PLN';
  for(const l of back.legs){[l.departure_airport,l.arrival_airport]=[l.arrival_airport,l.departure_airport];}
  const rt=JSON.stringify({...q,returnDate:day(34)});
  assert.notEqual(result('request',rt).url,result('request',rt,JSON.stringify(out)).url);
  const offer=result('offer',rt,JSON.stringify([JSON.stringify(out),JSON.stringify(back)]));
  assert.equal(offer.price,550);assert.equal(offer.journeys.length,2);
  back.price=null;back.currency=null;
  assert.equal(result('offer',rt,JSON.stringify([JSON.stringify(out),JSON.stringify(back)])).price,null);
});
test('blocked or malformed response is an error rather than zero flights',()=>{
  assert.throws(()=>result('decodePage',query,'<html>Consent required</html>'));
  assert.throws(()=>result('decodePage',query,"AF_initDataCallback({key: 'ds:1', data:[null], sideChannel: {}});"));
});
test('valid empty response stays empty',()=>{
  const empty="AF_initDataCallback({key: 'ds:1', data:[null,null,[[]],[[]]], sideChannel: {}});";
  assert.equal(result('decodePage',query,empty).rows.length,0);
});
test('rejects bad dates, backward trips and invalid airports',()=>{
  for(const changes of [{origin:'ZZZ'},{origin:'LHR'},{departureDate:'2020-01-01'},{departureDate:'2026-02-30'}, {returnDate:day(29)}, {adults:0}]){
    assert.throws(()=>result('request',JSON.stringify({...q,...changes})));
  }
});
test('airport lookup is offline and recognizes exact code first',()=>{
  assert.equal(result('airports','gdn')[0].code,'GDN');
  assert.ok(result('airports','Hamburg').some(x=>x.code==='HAM'));
});
