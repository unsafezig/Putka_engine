# PUTKA Engine

*A 2.5D top-down game engine built in **Zig** for GTA 2-style games and **human–AI collaborative game development**.*

---

## Overview

PUTKA Engine is a **deliberately focused game engine**. It is **not** trying to be Unity, Unreal, or a general-purpose engine. Instead, it is designed for a **specific class of games**:

- **2D top-down worlds**
- **Tile-based environments**
- **Vehicles and traffic**
- **Pedestrians and NPCs**
- **Weapons and combat**
- **Police and wanted systems**
- **Missions and branching stories**
- **Dialogue**
- **Radio and dynamic audio**
- **Large streamed city worlds**

The first game built with the engine is **PUTKA**, a Finnish crime game set in Kuusankoski.

**Long-term goal**: Build an engine where **humans design the world and the story**, while **AI agents can understand, modify, test, and debug the game** through structured tools.

---

## Why?

Modern AI coding agents are **very good at writing code**, but they struggle with questions like:

- Does this city actually feel right?
- Is this mission fun?
- Is the road layout understandable?
- Does this building belong here?
- Is this choice meaningful?
- Why does the game feel wrong?

A traditional codebase also gives an agent a **poor representation of a game**. A city may be represented by thousands of lines of code and asset references. A mission may be hidden inside arbitrary functions. The agent has to **reconstruct the game’s structure from implementation details**.

PUTKA Engine takes a **different approach**:

**The game itself becomes structured data.**

```
             HUMAN
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
 WORLD EDITOR      STORY EDITOR
       │                │
       └───────┬────────┘
               ▼
           GAME DATA
               │
        ┌──────┴──────┐
        │             │
        ▼             ▼
    AI AGENT      HUMAN PLAYTEST
        │             │
        └──────┬──────┘
               ▼
          ZIG ENGINE
```

---

## Design Principles

### 1. The Engine Is Not the Game
The engine knows generic concepts like:
- Player
- NPC
- Vehicle
- Weapon
- Building
- Mission
- Faction
- Police unit
- Trigger

The engine **does not** know game-specific details like who Timo is.

The **game** knows:
- Timo
- Kuusankoski
- Ekholmin bridge
- The hospital
- The city hall
- The story
- The characters
- The dialogue

**Key Principle**: This separation allows the same engine to power multiple games.

---

### 2. Human Designs, AI Implements
The human builds the world visually, and the AI agent implements it programmatically.

**Workflow**:
```
WORLD EDITOR → structured world data → AI agent → Zig implementation
```

**Example Mission Flow**:
```
START → HOSPITAL → WALK/STEAL → WANTED +1 → FUNERAL
```

---

### 3. Data-Driven Game Design
If a designer can change something without modifying engine code, it should be data.

**Example Directory Structure**:
```
data/
├── maps/
├── missions/
├── dialogue/
├── vehicles/
├── weapons/
├── characters/
├── factions/
└── radio/
```

---

## Core Features

### World
- Built from **tiles, sectors, and objects**
- Divided into **sectors** for efficient streaming and simulation
- Supports both small neighborhoods and large cities

**Structure**:
```
WORLD
├── sectors
│   ├── tiles
│   ├── buildings
│   ├── roads
│   ├── collision
│   ├── spawn points
│   └── triggers
└── global data
```

---

### Tile-Based Environment
Tiles have **semantic properties**:
- `ROAD`, `SIDEWALK`, `GRASS`, `WATER`, `WALL`, `BUILDING`, `BRIDGE`

Each tile can contain:
- Sprite
- Collision
- Material
- Flags

---

### Entities
Lightweight, handle-based entities:
```zig
const EntityId = struct { index: u32, generation: u32 };
```

**Entity Types**:
- `PLAYER`, `NPC`, `CAR`, `POLICE_CAR`, `WEAPON`, `OBJECT`, `TRIGGER`, `DOOR`

**Components**:
- `Transform`, `Sprite`, `Collider`, `Health`, `Character`, `Vehicle`, `AI`, `Faction`, `Weapon`, `Inventory`, `Interactable`, `MissionTarget`

---

### Vehicles
**First-class engine system** with arcade-style physics:
- Position, Velocity, Heading, Steering, Acceleration, Braking, Max Speed, Driver
- **Vehicle Types**: `CAR`, `POLICE`, `TRUCK`, `VAN`, `TAXI`, `EMERGENCY`

---

### Traffic
Roads form a **navigable graph**:
- Vehicles can follow roads, choose destinations, turn, stop, avoid obstacles, and reroute
- **Independent from mission logic**

---

### NPCs
**Deterministic AI** (not LLM-based):
- States: `IDLE`, `WALK`, `RUN`, `PANIC`, `FLEE`, `FIGHT`, `FOLLOW`, `ENTER_VEHICLE`, `EXIT_VEHICLE`

---

### Police and Wanted System
**Generic 6-level wanted system** (0-5):
- Game-specific rules determine how crimes affect wanted level
- **Flow**: `crime → severity → witness → police alert → wanted level`

---

### Factions
Relationships between entities:
- **Factions**: `PLAYER`, `POLICE`, `CIVILIANS`, `GANG_A`, `GANG_B`
- **Relationships**: `friendly`, `neutral`, `hostile`

---

### Weapons
**Data-driven weapon system**:
- Properties: Name, Damage, Range, Fire Rate, Ammo, Projectile Type, Sound
- Engine handles mechanics, game defines weapons

---

### Mission System
**Core feature** with support for:
- Prerequisites, Objectives, Triggers, Dialogue, Choices, Rewards, Consequences
- **Objective Types**: `GO_TO`, `TALK_TO`, `FOLLOW`, `STEAL`, `DELIVER`, `ESCAPE`, `PROTECT`, `SURVIVE`, `KILL`
- Designed for both linear and branching missions

---

### Branching Stories
**Explicit story state**:
```
story.father_dead = true
mission.hospital = complete
player.wanted = 1
```
- Choices modify state, state determines future content

---

### Dialogue
- Separate from mission logic
- Editable, localizable, inspectable by AI agents, reusable

---

### Radio
**First-class audio system**:
- Stations can contain: Music, DJ segments, News, Advertisements, Voice, Events
- Enables dynamic radio without changing audio engine

---

### Audio
Separates:
- Music, Sound Effects, Ambient Audio, Voice, Radio
- Audio events should be data-driven

---

### Camera
**Top-down camera system**:
- Modes: `PLAYER`, `VEHICLE`, `MISSION`, `CINEMATIC`
- Independent from rendering and gameplay

---

### Rendering
**Efficient rendering pipeline**:
```
visible sectors → tiles → static objects → entities → effects → UI
```
- Only visible sectors are rendered

---

### Collision
**Simple collision system**:
- Primitives: AABB (Axis-Aligned Bounding Box), Circle
- Separated from rendering

---

### Save System
**Serializable game state**:
- World state, Mission state, Story flags, Player inventory, Wanted level, Vehicle state, NPC state
- Independent from game-specific structures

---

### Agent Interface
**Structured interface for AI development**:
- `world.inspect`, `entity.inspect`, `mission.inspect`, `story.inspect`
- `vehicle.inspect`, `npc.inspect`, `police.inspect`
- `screenshot`, `play`, `pause`, `step`, `spawn`, `teleport`, `set_state`, `run_scenario`

**Example**:
```
Agent asks: "Why can't the player enter the city hall?"
Engine responds:
MISSION FAILED
Objective: Enter city hall
Trigger: city_hall_door_01
Collision: BLOCKED
Entity: player
Blocking object: building_42
```

---

## Human-in-the-Loop Development

### Human Responsibilities
- Game vision, World design, Story, Gameplay decisions
- Art direction, Playtesting, Final approval

### AI Agent Responsibilities
- Implementation, Refactoring, Debugging
- Content generation, Test scenarios, Technical investigation
- Repetitive work

### Engine Responsibilities
- Structured world, Deterministic simulation
- Rendering, Physics, Missions, AI
- Audio, Saves, Inspection tools

---

## Editor Tools

### World Editor
- Paint/erase tiles, Create roads, Place buildings/objects
- Place spawn points, Create triggers, Edit collision

### Mission Editor
- Visually construct mission flow, objectives, dialogue
- Define choices, conditions, consequences

---

## Project Architecture

```
putka-engine/
├── engine/
│   ├── core/
│   ├── math/
│   ├── memory/
│   ├── assets/
│   ├── world/
│   ├── rendering/
│   ├── entities/
│   ├── physics/
│   ├── vehicles/
│   ├── characters/
│   ├── weapons/
│   ├── police/
│   ├── missions/
│   ├── dialogue/
│   ├── audio/
│   ├── input/
│   ├── camera/
│   ├── ui/
│   ├── save/
│   ├── scripting/
│   └── debugging/
├── editor/
│   ├── world/
│   ├── missions/
│   ├── entities/
│   ├── dialogue/
│   └── inspector/
├── game/
│   └── putka/
└── data/
    └── putka/
        ├── maps/
        ├── missions/
        ├── dialogue/
        ├── vehicles/
        ├── weapons/
        ├── characters/
        └── radio/
```

---

## Zig Language

**Why Zig?**
- Explicit memory management
- Predictable performance
- Simple build tooling
- Low-level control
- Strong compile-time facilities
- Single language for engine and game code

**Principle**: Favor understandable Zig over unnecessary abstraction

---

## Development Roadmap

### Phase 1: Engine Foundation
- [ ] Zig project structure
- [ ] Window
- [ ] Input
- [ ] Renderer
- [ ] Camera
- [ ] Tile map
- [ ] Collision
- [ ] Entity system
- [ ] Player

### Phase 2: GTA-Style World
- [ ] Sectors
- [ ] Buildings
- [ ] Roads
- [ ] NPCs
- [ ] Vehicles
- [ ] Vehicle physics
- [ ] Traffic
- [ ] World streaming

### Phase 3: Crime Systems
- [ ] Weapons
- [ ] Combat
- [ ] Factions
- [ ] Police
- [ ] Wanted system
- [ ] NPC reactions

### Phase 4: Story Systems
- [ ] Mission system
- [ ] Objectives
- [ ] Dialogue
- [ ] Choices
- [ ] Branching state
- [ ] Consequences
- [ ] Save/load

### Phase 5: Content Tools
- [ ] World editor
- [ ] Mission editor
- [ ] Entity inspector
- [ ] Dialogue editor
- [ ] Asset management

### Phase 6: AI Development Interface
- [ ] World inspection
- [ ] Entity inspection
- [ ] Mission inspection
- [ ] Story inspection
- [ ] Screenshots
- [ ] Play/pause/step
- [ ] Scenario runner
- [ ] State manipulation
- [ ] Automated playtesting

### Phase 7: PUTKA Game
- [ ] Kuusankoski world
- [ ] Characters
- [ ] Missions
- [ ] Story
- [ ] Police system
- [ ] Vehicles
- [ ] Weapons
- [ ] Radio
- [ ] Complete playable campaign

---

## Scope

**What PUTKA Engine is NOT**:
- A 3D engine
- A general-purpose game engine
- A realistic physics simulator
- An MMORPG framework
- A Unity/Unreal replacement

**What it IS**: A focused engine for 2D top-down, systemic, city-based games

---

## Long-Term Vision

```
PUTKA (Kuusankoski) → Larger World → Multiple Cities → New Games
```

Same engine supports all scales without architectural changes

---

## Philosophy

**Traditional approach**: "How do we make the computer understand what the designer wants?"

**PUTKA approach**: "How do we make the game understandable to both the human designer and the AI developer?"

**Core Values**:
- Explicit, inspectable, editable game state
- Human creates, AI helps build, engine enables understanding

---

## Status

🚧 **Early development**
- Architecture designed alongside PUTKA game
- Evolves from actual gameplay requirements

---

## License

**GNU General Public License v3.0 (GPL 3)**.
