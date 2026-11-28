class_name Config
extends RefCounted
## Every tunable of the prototype. Nothing is read from data files.

const SEED := 1
const EPOCH_ANGLES_DEG := {"Earth": 0, "Moon": 0, "Mars": 45}
const CYCLE_DAYS := 780.0
const SHORT_LEG_DAYS := 146.0

## Name, direction and phase day of each cycler.
const CYCLERS := [
	{"name": "Aldrin I", "direction": "UP", "phase_day": 0},
	{"name": "Aldrin II", "direction": "DOWN", "phase_day": 130},
	{"name": "Aldrin III", "direction": "UP", "phase_day": 260},
	{"name": "Aldrin IV", "direction": "DOWN", "phase_day": 390},
	{"name": "Aldrin V", "direction": "UP", "phase_day": 520},
	{"name": "Aldrin VI", "direction": "DOWN", "phase_day": 650},
]

## `service` is "shuttle", "tender", "express", "standby" or "spare". `home` is
## a body name, or the cycler name a standby ship is docked to.
const TRANSPORTS: Array[Dictionary] = [
	{"name": "Kestrel", "service": "shuttle", "home": "Earth"},
	{"name": "Heron", "service": "shuttle", "home": "Earth"},
	{"name": "Osprey", "service": "shuttle", "home": "Earth"},
	{"name": "Wren", "service": "shuttle", "home": "Earth"},
	{"name": "Swift", "service": "shuttle", "home": "Moon"},
	{"name": "Falcon", "service": "shuttle", "home": "Moon"},
	{"name": "Merlin", "service": "shuttle", "home": "Moon"},
	{"name": "Harrier", "service": "shuttle", "home": "Moon"},
	{"name": "Plover", "service": "tender", "home": "Earth"},
	{"name": "Egret", "service": "tender", "home": "Earth"},
	{"name": "Ibis", "service": "tender", "home": "Earth"},
	{"name": "Tern", "service": "tender", "home": "Earth"},
	{"name": "Petrel", "service": "tender", "home": "Earth"},
	{"name": "Gannet", "service": "tender", "home": "Mars"},
	{"name": "Curlew", "service": "tender", "home": "Mars"},
	{"name": "Dunlin", "service": "tender", "home": "Mars"},
	{"name": "Lark", "service": "tender", "home": "Mars"},
	{"name": "Finch", "service": "tender", "home": "Mars"},
	{"name": "Linnet", "service": "express", "home": "Earth"},
	{"name": "Robin", "service": "express", "home": "Earth"},
	{"name": "Starling", "service": "express", "home": "Mars"},
	{"name": "Thrush", "service": "express", "home": "Mars"},
	{"name": "Shrike", "service": "standby", "home": "Aldrin I"},
	{"name": "Sparrow", "service": "standby", "home": "Aldrin II"},
	{"name": "Martin", "service": "standby", "home": "Aldrin III"},
	{"name": "Kite", "service": "standby", "home": "Aldrin IV"},
	{"name": "Hobby", "service": "standby", "home": "Aldrin V"},
	{"name": "Avocet", "service": "standby", "home": "Aldrin VI"},
	{"name": "Godwit", "service": "spare", "home": "Earth"},
	{"name": "Puffin", "service": "spare", "home": "Mars"},
]

const SEATS := {"cycler": 400, "shuttle": 20, "tender": 20, "express": 8, "standby": 20, "spare": 20}

const WINDOW_DAYS := 800.0
const CONNECTION_DAYS := 0.25
const WARMUP_START := -400.0
const ARRIVED_LINGER_DAYS := 10.0

const SHUTTLE_TURNAROUND_DAYS := 0.5
const EXPRESS_TURNAROUND_DAYS := 3.0
## A rescue transport waits this long at its stop before flying back to its cycler.
const RESCUE_TURNAROUND_DAYS := 1.0
## The i-th ship of a service at one body first departs i times this after the warm-up starts.
const SHUTTLE_STAGGER_DAYS := 0.35
const EXPRESS_STAGGER_DAYS := 12.0
## A tender leaves its planet this long before a flyby, and leaves the cycler
## this long after it.
const TENDER_LEAD_DAYS := 1.0
const TENDER_LINGER_DAYS := 1.0

## Daily chance that a party changes its mind, by reason for travel. A party
## uses the highest chance among its members.
const CHANGE_OF_MIND := {"VISIT": 0.004, "WORK": 0.002, "RETURNING": 0.002, "MEDICAL": 0.001, "EMIGRATION": 0.0005}
## From this age, each year raises the risk of an emergency and its severity.
const AGE_RISK_START_YEAR := 40
## A condition's daily chance is multiplied by 1 + (age - AGE_RISK_START_YEAR) * this.
const AGE_RISK_PER_YEAR := 0.02
## The chance an emergency is CRITICAL: the base, plus this for each year of age past the start year.
const CRITICAL_BASE := 0.2
const CRITICAL_PER_YEAR := 0.005
## Daily chance, per ship, of each kind of malfunction.
const DOCKING_FAILURE_CHANCE := 0.003
const LIFE_SUPPORT_CHANCE := 0.002
## The range, in whole days, of a CRITICAL patient's stable period and of a hospital stay.
const STABLE_DAYS := [5, 20]
const HOSPITAL_STAY_DAYS := [7, 21]
