"""Core value types, mirroring the macOS app's LocationModels.swift."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


@dataclass
class LocationPoint:
    """A coordinate, optionally named and timestamped."""

    name: str = ""
    latitude: float = 0.0
    longitude: float = 0.0
    timestamp: Optional[float] = None  # epoch seconds
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    @property
    def is_valid(self) -> bool:
        return -90.0 <= self.latitude <= 90.0 and -180.0 <= self.longitude <= 180.0

    @property
    def coordinate_label(self) -> str:
        return f"{self.latitude:.6f}, {self.longitude:.6f}"

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "latitude": self.latitude,
            "longitude": self.longitude,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "LocationPoint":
        return cls(
            name=data.get("name", ""),
            latitude=float(data.get("latitude", 0.0)),
            longitude=float(data.get("longitude", 0.0)),
        )


@dataclass
class SavedPlace:
    name: str
    point: LocationPoint
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def to_dict(self) -> dict:
        return {"name": self.name, "point": self.point.to_dict()}

    @classmethod
    def from_dict(cls, data: dict) -> "SavedPlace":
        return cls(
            name=data.get("name", ""),
            point=LocationPoint.from_dict(data.get("point", {})),
        )


@dataclass
class DeviceTarget:
    """A connected iPhone.

    Unlike macOS, Windows has no iOS Simulator, so every target is a physical device
    reached over usbmux (Apple Mobile Device Service).
    """

    udid: str
    name: str
    model: str = "iPhone"
    os_version: str = ""
    connection: str = "USB"
    is_available: bool = True

    @property
    def detail(self) -> str:
        parts = [p for p in (self.model, self.os_version, self.connection) if p]
        return " · ".join(parts)


class SimulationState(Enum):
    IDLE = "idle"
    PREPARING = "preparing"
    ACTIVE = "active"
    PLAYING = "playing"
    STOPPING = "stopping"
    FAILED = "failed"

    @property
    def is_running(self) -> bool:
        return self in (
            SimulationState.PREPARING,
            SimulationState.ACTIVE,
            SimulationState.PLAYING,
            SimulationState.STOPPING,
        )


class RelocateError(Exception):
    """Base error surfaced to the UI."""


class NoDeviceError(RelocateError):
    def __str__(self) -> str:
        return "Select an available device first."


class InvalidCoordinateError(RelocateError):
    def __str__(self) -> str:
        return "Latitude must be between -90 and 90; longitude between -180 and 180."


class MalformedGPXError(RelocateError):
    def __str__(self) -> str:
        return "The GPX file does not contain valid track points."
