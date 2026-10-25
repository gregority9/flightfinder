// Calls only Fli's pure encoders/decoders. URLSession owns networking on iPhone.
import { AIRPORT_NAMES } from '@fli/models/airport.ts';
import { buildTfs, extractPayload, pageUrl } from '@fli/search/tfs.ts';
import { parseFlightRow } from '@fli/search/decoders.ts';
import { buildTfsToken } from '@fli/search/proto.ts';
import { setSearchLogger } from '@fli/search/logging.ts';
setSearchLogger({warn(){},debug(){}});

function envelope(fn:()=>unknown):string {
  try { return JSON.stringify({data:fn()}); }
  catch(e) { return JSON.stringify({error:e instanceof Error?e.message:String(e)}); }
}
function local(d:Date):string {
  const p=(n:number)=>String(n).padStart(2,'0');
  return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:00`;
}
function revive(raw:string):any {
  const f=JSON.parse(raw);
  f.legs.forEach((l:any)=>{ l.departure_datetime=new Date(l.departure_datetime); l.arrival_datetime=new Date(l.arrival_datetime); });
  return f;
}
function validate(text:string):any {
  const q=JSON.parse(text);
  if(!AIRPORT_NAMES[q.origin]||!AIRPORT_NAMES[q.destination]||q.origin===q.destination)throw Error('Wybierz dwa różne lotniska z listy.');
  if(!Number.isInteger(q.adults)||q.adults<1||q.adults>9)throw Error('Wybierz od 1 do 9 dorosłych.');
  if(!['PLN','EUR','TRY','USD','GBP'].includes(q.currency))throw Error('Nieobsługiwana waluta.');
  if(![0,1,2].includes(q.maxStops))throw Error('Nieprawidłowy limit przesiadek.');
  if(!['ECONOMY','PREMIUM_ECONOMY','BUSINESS','FIRST'].includes(q.cabin))throw Error('Nieprawidłowa klasa.');
  const today=local(new Date()).slice(0,10);
  for(const day of [q.departureDate,q.returnDate].filter(Boolean)) {
    if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||Number.isNaN(new Date(day+'T12:00:00').getTime())||local(new Date(day+'T12:00:00')).slice(0,10)!==day)throw Error('Nieprawidłowa data.');
    if(day<today)throw Error('Data lotu jest w przeszłości.');
    if((new Date(day+'T12:00:00').getTime()-Date.now())/86400000>330)throw Error('Wyszukiwanie do 330 dni naprzód.');
  }
  if(q.returnDate&&q.returnDate<q.departureDate)throw Error('Powrót nie może być przed wylotem.');
  return q;
}
function filters(q:any,selected?:string):any {
  const segment=(o:string,d:string,date:string)=>({departure_airport:[[[o,0]]],arrival_airport:[[[d,0]]],travel_date:date,selected_flight:null});
  const segments:any[]=[segment(q.origin,q.destination,q.departureDate)];
  if(q.returnDate)segments.push(segment(q.destination,q.origin,q.returnDate));
  if(selected)segments[0].selected_flight=revive(selected);
  return {trip_type:q.returnDate?1:2,passenger_info:{adults:q.adults,children:0,infants_in_seat:0,infants_on_lap:0},flight_segments:segments,stops:q.maxStops+1,seat_type:['ECONOMY','PREMIUM_ECONOMY','BUSINESS','FIRST'].indexOf(q.cabin)+1};
}
function journey(f:any) {
  return {duration:f.duration,stops:f.stops,legs:f.legs.map((l:any)=>({origin:l.departure_airport,destination:l.arrival_airport,departure:local(l.departure_datetime),arrival:local(l.arrival_datetime),airline:l.airline.replace(/^_/,''),flightNumber:String(l.flight_number),duration:l.duration}))};
}
export function request(query:string,selected?:string):string {
  return envelope(()=>{const q=validate(query);return {url:pageUrl(buildTfs(filters(q,selected)),q.currency,'pl','PL')};});
}
export function airports(text:string):string {
  return envelope(()=>{
    const term=text.trim().toLocaleLowerCase();
    return Object.entries(AIRPORT_NAMES).filter(([c,n])=>c.toLowerCase().includes(term)||n.toLocaleLowerCase().includes(term))
      .sort(([a],[b])=>(a.toLowerCase()===term?-1:b.toLowerCase()===term?1:a.localeCompare(b)))
      .slice(0,30).map(([code,name])=>({code,name}));
  });
}
export function decodePage(query:string,html:string):string {
  return envelope(()=>{
    const q=validate(query), inner=extractPayload(html) as any;
    if(!Array.isArray(inner))throw Error('Google nie udostępniło wyników. Możliwa blokada lub ekran zgody. Spróbuj później lub w innej sieci.');
    const raw:any[]=[];
    for(const i of [2,3]) {
      if(i>=inner.length)throw Error('Zmieniony format danych Google Flights.');
      if(inner[i]==null)continue;
      if(!Array.isArray(inner[i])||!Array.isArray(inner[i][0]))throw Error('Zmieniony format danych Google Flights.');
      raw.push(...inner[i][0]);
    }
    const parsed:any[]=[];
    for(const row of raw) {
      try {
        const f=parseFlightRow(row);
        if(!f.legs.length||!Number.isFinite(f.duration)||f.duration<=0)continue;
        if(f.stops>q.maxStops)continue;
        const wire=JSON.stringify({...f,legs:f.legs.map(l=>({...l,departure_datetime:local(l.departure_datetime),arrival_datetime:local(l.arrival_datetime)}))});
        parsed.push({wire,price:f.price,currency:f.currency});
      }catch{}
    }
    if(raw.length&&!parsed.length)throw Error('Nie udało się odczytać lotów albo żaden nie spełnia filtrów. Spróbuj zmienić przesiadki.');
    parsed.sort((a,b)=>(a.price??Infinity)-(b.price??Infinity));
    return {rows:parsed};
  });
}
export function offer(query:string,rawRows:string):string {
  return envelope(()=>{
    const q=validate(query), rows=JSON.parse(rawRows).map(revive), last=rows[rows.length-1];
    if(rows.length!==(q.returnDate?2:1))throw Error('Niekompletna podróż.');
    const journeys=rows.map(journey);
    const id=journeys.flatMap((j:any)=>j.legs.map((l:any)=>`${l.airline}${l.flightNumber}:${l.departure}`)).join('|');
    const segments=rows.map((f:any)=>f.legs.map((l:any)=>({origin:l.departure_airport,dest:l.arrival_airport,depDate:local(l.departure_datetime).slice(0,10),airline:l.airline.replace(/^_/,''),flightNumber:String(l.flight_number)})));
    const tfs=buildTfsToken(segments,{isOneWay:!q.returnDate,passengers:Array(q.adults).fill(1),seat:filters(q).seat_type});
    return {id,price:Number.isFinite(last.price)?last.price:null,currency:last.currency??null,journeys,
      bookingUrl:`https://www.google.com/travel/flights/booking?tfs=${tfs}&curr=${q.currency}&hl=pl&gl=PL`};
  });
}
