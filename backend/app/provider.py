import hashlib
import time
from threading import Lock

from fli.models import (
    Airport, FlightSearchFilters, FlightSegment, MaxStops,
    PassengerInfo, SeatType, SortBy, TripType,
)
from fli.search import SearchFlights

from .models import Journey, Leg, Offer, Search, SearchResponse
from .store import now


def filters_for(query: Search):
    def segment(origin, destination, day):
        return FlightSegment(
            departure_airport=[(Airport[origin], 0)],
            arrival_airport=[(Airport[destination], 0)],
            travel_date=day.isoformat(),
        )
    segments = [segment(query.origin, query.destination, query.departure_date)]
    if query.return_date:
        segments.append(segment(query.destination, query.origin, query.return_date))
    return FlightSearchFilters(
        trip_type=TripType.ROUND_TRIP if query.return_date else TripType.ONE_WAY,
        passenger_info=PassengerInfo(adults=query.adults),
        flight_segments=segments,
        seat_type=SeatType[query.cabin],
        stops=[MaxStops.NON_STOP, MaxStops.ONE_STOP_OR_FEWER, MaxStops.TWO_OR_FEWER_STOPS][query.max_stops],
        sort_by=SortBy.CHEAPEST,
    )


def normalize(result, client, query):
    flights = list(result) if isinstance(result, tuple) else [result]
    # Fli's round-trip serializer uses the outbound row as the full RT price.
    # Adding outbound + return would double-count. Unknown currencies stay unknown.
    priced = flights[0]
    journeys = [Journey(
        duration=f.duration, stops=f.stops,
        legs=[Leg(
            origin=leg.departure_airport.name,
            destination=leg.arrival_airport.name,
            departure=leg.departure_datetime.isoformat(),
            arrival=leg.arrival_datetime.isoformat(),
            airline=leg.airline.name.lstrip("_"), flight_number=leg.flight_number,
            duration=leg.duration,
        ) for leg in f.legs],
    ) for f in flights]
    identity = "|".join(f"{l.airline}{l.flight_number}:{l.departure}" for j in journeys for l in j.legs)
    return Offer(
        id=hashlib.sha256(identity.encode()).hexdigest()[:24],
        price=priced.price, currency=priced.currency, journeys=journeys,
        booking_url=client.build_flight_booking_url(
            result, currency=query.currency, language="pl", country="PL",
            seat_type=SeatType[query.cabin], passenger_info=PassengerInfo(adults=query.adults),
        ),
    )


class Provider:
    def __init__(self):
        self.cache = {}
        # Bound upstream concurrency. One fresh client per search; never share sessions.
        self.lock = Lock()

    def search(self, query: Search, fresh=False):
        query.check_future()
        key = query.model_dump_json()
        with self.lock:
            if not fresh and key in self.cache:
                expiry, response = self.cache[key]
                if expiry > time.monotonic():
                    return response.model_copy(update={"cached": True}, deep=True)
            client = SearchFlights()
            results = client.search(filters_for(query), top_n=5, currency=query.currency, language="pl", country="PL")
            offers = [normalize(r, client, query) for r in results or []]
            offers.sort(key=lambda o: (o.price is None, o.price or 0))
            response = SearchResponse(query=query, offers=offers, checked_at=now())
            self.cache = {k: v for k, v in self.cache.items() if v[0] > time.monotonic()}
            if len(self.cache) >= 100:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = (time.monotonic() + 300, response)
            return response
