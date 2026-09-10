# Icon Grid Keyboard Parity Design

## Problem

The Icon Grid renders standalone buttons while the Compact List renders `HubItemRow`. Keyboard navigation updates `HubPanelModel.selectionID`, but grid cells do not display that selection. The grid also ignores `actionMenuPresentationID`, so Command-K cannot present the selected item's actions.

## Considered approaches

1. **Share one interactive item component (selected).** Let `HubItemRow` render either a row or a grid cell while retaining one action-menu state machine, accessibility presentation, context menu, feedback state, and keyboard selection contract. This removes the behavioral fork with a focused change.
2. Duplicate the row's action menu and selection behavior in `HubPanelView.iconGrid`. This is faster initially but creates two implementations that can diverge again.
3. Disable or document reduced keyboard behavior in grid mode. This contradicts macOS keyboard conventions and the published shortcut contract.

## Interaction contract

- Up and Down update the selected grid item and show an accent-colored rounded selection state.
- Return invokes the selected item; Command-Return opens its host app.
- Command-K opens the same anchored action popover used by the compact list.
- Command-1 through Command-9 invoke favorites, Command-F focuses search, and Escape keeps its existing behavior.
- Hover reveals the more-actions affordance. Right-click presents the same context menu as list mode.
- Grid items expose the same accessibility identifier, label, value, and hint as list items.

## Scope and verification

No catalog, Accessibility permission, persistence, scan, or release behavior changes. Verification consists of model/unit tests, a focused XCUITest that launches the deterministic grid fixture and opens actions with the keyboard, the full Swift test suite, and a local release build/install check.
