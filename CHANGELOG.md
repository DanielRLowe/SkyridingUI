# SkyridingUI Changelog

## Version 1.4.5 — Grounded-State Hiding Options

### New Features
- **Hide UI when grounded with full charges**: Added option to automatically hide the entire UI when landed and all vigor charges are full
- **Hide Speed/Acceleration when grounded**: Added option to hide flight speed and acceleration displays when grounded (affects Horizontal, Speedometer, and Circular modes)

### Bug Fixes
- **Fixed Circular speed ring background**: Speed ring background segments now properly hide when grounded (previously only the fill was hiding)

---

## Version 1.4.4 — Circular Options Menu Improvements

### New Features
- **Circular visibility toggles**: Added checkboxes to show/hide individual elements (Speed Ring, Charge Arcs, Center Glow, Surge Arc, Second Wind)
- **Circular charge arc colors**: Added color pickers for charge arcs (Full Charge, Charging, Empty) - shared with Horizontal mode

---

## Version 1.4.3 — Horizontal Options Menu Improvements

### New Features
- **Horizontal Bar visibility toggles**: Added checkboxes to show/hide individual elements (Speed Bar, Charge Bars, Acceleration Bar, Whirling Surge Bar, Second Wind Bars)
- **Horizontal Bar padding sliders**: Control spacing between charge bars and Second Wind bars
- **Circular visibility toggles**: Added checkboxes to show/hide Speed Ring, Charge Arcs, Center Glow, Surge Arc, and Second Wind
- **Circular charge arc colors**: Added color pickers for charge arcs (shared with Horizontal mode)
- **Scrollable options menu**: Options panel now scrolls to accommodate all settings

---

## Version 1.4.2 — Bugfixes & Improvements

### Bug Fixes
- **Fixed Second Wind bars displaying incorrectly**: Bars higher than the currently charging one now properly show as empty instead of retaining stale partial fills
- **Fixed minimap button icon positioning**: Icon now properly centered within the circular border

### Changes
- **Speedometer Whirling Surge indicator**: Changed from arc-based to horizontal bar display for cleaner appearance. Bar now appears below the charge progress bar

---

## Version 1.4.1 — Bugfix

### Bug Fixes
- **Fixed Circular and Speedometer modes not working**: After the 1.4.0 refactoring, Circular mode was not showing the acceleration indicator and Speedometer mode's needle wasn't moving. Both modules now correctly calculate speed and acceleration independently.

---

## Version 1.4.0 — Vigor UI and Options Overhaul

### Changes
- **Completely redesigned Vigor bar**, featuring new custom artwork, improved animations, and a more polished overall look.
- **Updated options menu** with a cleaner layout and streamlined settings. (Additional customization options planned for future updates.)

---

## Version 1.3.0 - Classic Vigor Bar (Removed)

**Note**: This version's Vigor display was removed due to licensing issues.

---

## Version 1.2.0 - Circular Display & Minimap Button

### New Features
- **New Circular UI Mode**: Added a third display style - a minimalistic radial meter optimized for center-screen HUD overlay
  - **Full 360° Outer Ring**: Flight speed displayed as a smooth gradient fill circle (540 segments for seamless appearance)
  - **Inner Charge Arcs**: Six arc segments for movement skill charges with customizable colors
  - **Inner Surge Ring**: Thin green ring showing Whirling Surge cooldown progress
  - **Second Wind Indicators**: Three vertical bars positioned at 3 o'clock for Second Wind recharge status
  - **Speed Color Dynamics**: White/gray gradient normally, transitions to blue when Thrill of the Skies buff is active
  - **Center Glow**: Acceleration state indicator (yellow for accelerating, red for decelerating)
  - **Charge Color Sync**: Circular mode now uses the same customizable charge colors as bar mode
  - Compact design (120px) optimized for placement directly over your character
- **Minimap Button**: Added draggable minimap button for easy access to options
  - Left-click to open options menu
  - Right-click to toggle frame lock
  - Drag to reposition around the minimap
  - Toggle visibility via "Show Minimap Button" checkbox in Visibility tab
- **Addon Compartment Support**: Integration with modern WoW's addon compartment (minimap dropdown)
- **Blizzard Interface Panel**: Accessible via ESC → Options → AddOns → Skyriding UI
- New "Circular" option in UI Style selection (Visibility tab)

### Technical
- Added new `Circular.lua` module for radial display
- Added minimap button with drag-around-minimap functionality
- Added Blizzard Settings API integration for addon panel
- Circular mode uses 1080 speed segments, 24 segments per charge, 120 surge segments
- 0.5° segment overlap mostly eliminates visible gaps
- Charge colors read from SkyridingUIDB settings for consistency across all modes

---

## Version 1.1.4 - Druid Flight Form Support

### New Features
- **Druid Flight Form Support**: UI now properly detects and displays immediately when Druids shift into Travel Form (flight mode)
- Added detection for all Druid flight form variants (Travel Form, Flight Form, Bat Form)

### Bug Fixes
- Fixed UI not appearing until gliding when using Druid flight form
- Improved form/mount detection to include shapeshifting abilities

### Technical
- Added `IsInDruidFlightForm()` function to detect Druid flight forms
- Added support for multiple Druid flight form spell IDs (783, 165962, 276029)
- Enhanced `IsOnSkyridingMount()` to check for Druid flight forms before mount detection

---

## Version 1.1.3 - Mount Detection Fix

### Bug Fixes
- **Fixed UI appearing on ground mounts**: Resolved issue where the UI would incorrectly show when mounting ground-only mounts
- **Improved mount detection**: Reworked mount detection logic to properly differentiate between dragonriding mounts and ground mounts
- **Eliminated flickering**: Fixed UI flickering when mounting/dismounting by improving state detection
- **Immediate display on flying mounts**: UI now appears immediately when mounting a dragonriding mount in flyable areas without delay

### Technical
- Replaced mount type checking with spell usability detection for more reliable mount identification
- Added `IsOnSkyridingMount()` function to check if mounted on a dragonriding-capable mount
- Improved event handler timing to prevent race conditions during mount transitions

---

## Version 1.1.2 - Danger Zone Toggle

### New Features
- **Speedometer Danger Zone Highlighting**: Added optional red coloring for 1000-1200% speed range on speedometer
  - New checkbox in Colors tab: "Highlight Danger Zone (1000-1200% in Red)"
  - When enabled, tick marks and labels in the 1000-1200% range display in red
  - Disabled by default to maintain clean aesthetic
  - Helps identify when you're in the extreme high-speed range

### Improvements
- Speedometer tick marks and labels now dynamically update when danger zone toggle is changed
- Default speedometer appearance remains clean with white and blue colors only

---

## Version 1.1.1 - Options Parity Update

### Improvements
- **Unified Options**: UI Scale slider now affects both bar and speedometer modes
- **Background Opacity**: Background opacity slider now works for speedometer mode
- **Element Visibility**: All visibility toggles (Second Wind, Whirling Surge, Charges) now work for speedometer mode
- The speedometer now respects all the same customization options as the bar mode

### Bug Fixes
- Fixed UI Scale slider not affecting speedometer size
- Fixed background opacity not applying to speedometer backgrounds
- Fixed visibility options not hiding/showing speedometer elements
- Speedometer now properly updates when options are changed

---

## Version 1.1.0 - Speedometer Update

### Major Features
- **NEW: Analog Speedometer Display Mode**
  - Added a completely new speedometer-style UI as an alternative to the traditional bar layout
  - Features a circular gauge with rotating needle that points to your current speed
  - Thrill of the Skies (789%) speed positioned at 12 o'clock for easy reference
  - Needle and digital display change color when Thrill buff is active (blue)
  - Includes tick marks at 0%, 400%, 789%, 1000%, and 1200% with labels
  - Toggle between bar mode and speedometer mode via dropdown in options menu

### Speedometer Features
- **Speed Display**: Large digital readout with analog needle on circular gauge
- **Whirling Surge Tracking**: Green arc around the speedometer edge that depletes right-to-left as cooldown expires
- **Second Wind Charges**: Three horizontal bars below the speed text showing Second Wind charges
- **Ability Charges**: "Charges: X" display with progress bar showing current charge filling
- **Background Toggle**: Background visibility setting now works for both UI modes
- **Independent Positioning**: Speedometer has its own position settings, separate from bar mode

### UI/Options Improvements
- Added "UI Mode" dropdown in options to switch between "Bars" and "Speedometer"
- Speedometer shares the same background visibility toggle as bar mode
- All tracking features work seamlessly in both UI modes

### Technical
- Created new `Speedometer.lua` module for analog gauge implementation
- Added `rawSpeed` tracking to ensure accurate speed readings in all zones
- Improved speed calculation to handle slow skyriding zones correctly

### Bug Fixes
- Fixed speedometer speed calculation showing incorrect values (929% vs 789%)
- Fixed Whirling Surge arc depletion direction (now correctly goes right-to-left)
- Fixed Second Wind bar positioning to avoid UI overlap
- Fixed charge display progress bar tracking
- Fixed background toggle to apply to both UI modes

---

## Version 1.0.0 - Initial Release

### Core Features
- Speed bar with percentage display
- Acceleration bar (green/red for accel/decel)
- 6 ability charge bars with individual cooldown tracking
- Whirling Surge duration bar
- Second Wind charge tracking (3 bars)
- Support for slow skyriding zones

### Customization
- Fully movable and scalable interface
- Lock/unlock toggle
- Individual element visibility toggles
- Individual bar dimension controls (width/height)
- Color customization for all elements
- Background opacity controls
- Global and per-bar padding settings

### Options Menu
- Tabbed interface (Size & Position, Colors, Visibility)
- Reset to defaults button
- Load condition: Hide in non-flyable areas
