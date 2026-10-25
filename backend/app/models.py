from datetime import date, datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from fli.models.airport import AIRPORT_NAMES


class Search(BaseModel):
    model_config = ConfigDict(extra="forbid")
    origin: str
    destination: str
    departure_date: date
    return_date: date | None = None
    adults: int = Field(default=1, ge=1, le=9)
    currency: Literal["PLN", "EUR", "TRY", "USD", "GBP"] = "PLN"
    max_stops: int = Field(default=1, ge=0, le=2)
    cabin: Literal["ECONOMY", "PREMIUM_ECONOMY", "BUSINESS", "FIRST"] = "ECONOMY"

    @field_validator("origin", "destination")
    @classmethod
    def airport(cls, value):
        value = value.strip().upper()
        if value not in AIRPORT_NAMES:
            raise ValueError("Nieznany kod lotniska IATA")
        return value

    @model_validator(mode="after")
    def validate_route(self):
        if self.origin == self.destination:
            raise ValueError("Wybierz różne lotniska")
        if self.return_date and self.return_date < self.departure_date:
            raise ValueError("Powrót nie może być przed wylotem")
        return self

    def check_future(self):
        # Origin-local dates can be a day behind UTC.
        today = datetime.now(timezone.utc).date()
        if self.departure_date < today - timedelta(days=1):
            raise ValueError("Data wylotu jest w przeszłości")
        if (self.return_date or self.departure_date) > today + timedelta(days=330):
            raise ValueError("Wyszukiwanie jest dostępne do 330 dni naprzód")


class AlertCreate(BaseModel):
    query: Search
    target_price: float = Field(gt=0, le=1_000_000, allow_inf_nan=False)


class Device(BaseModel):
    token: str = Field(min_length=32, max_length=512, pattern=r"^(?:[0-9a-fA-F]{2})+$")


class Leg(BaseModel):
    origin: str
    destination: str
    departure: str
    arrival: str
    airline: str
    flight_number: str
    duration: int


class Journey(BaseModel):
    legs: list[Leg]
    duration: int
    stops: int


class Offer(BaseModel):
    id: str
    price: float | None
    currency: str | None
    journeys: list[Journey]
    booking_url: str


class SearchResponse(BaseModel):
    query: Search
    offers: list[Offer]
    checked_at: str
    cached: bool = False
    note: str = "Cena łącznie dla wszystkich pasażerów. Potwierdź cenę i bagaż przed zakupem."
