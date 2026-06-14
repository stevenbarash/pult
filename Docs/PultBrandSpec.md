# Pult Brand Spec

Pult uses a functional living-room console direction: fast controls, compact status, and a cool graphite glass surface that feels native on modern iOS without leaning on generic blue/purple gradients or decorative hero art.

## Design Direction

- School: Functional with cool minimal surfaces.
- Primary use: repeated couch-side TV control in dim rooms.
- Signature detail: a tactile remote deck with aqua touch feedback and subtle dial guide lines.
- UI density: compact on the remote, comfortable in setup and validation sheets.

## Palette

- Accent aqua: `#56D6C9`
- Deep aqua: `#178CA3`
- Soft aqua: `#D9FFF7`
- Ink: `#F4FAF8`
- Muted ink: `#AAB8B5`
- Carbon top: `#101416`
- Carbon middle: `#171D20`
- Carbon bottom: `#070A0C`
- Connected green: `#7BD99A`
- Utility steel: `#9FB8D9`
- Warning apricot: `#F2A65D`
- Danger coral: `#FF6A63`

Use aqua for active controls, focus, and primary calls to action. Use green only for connected or validated state. Use utility steel for volume/media-adjacent affordances. Use apricot only for warning and review states, not brand identity. Avoid default system blue except where the system requires it.

## Type

- Display: SwiftUI system serif, 30pt bold.
- Small display: SwiftUI system serif, 22pt bold.
- Heading: SF Pro, 20pt semibold.
- Subhead: SF Pro, 17pt semibold.
- Body: SF Pro, 16pt regular.
- Caption: SF Pro, 12pt regular or semibold.

## Spacing And Shape

- Base grid: 4pt, favor 8pt increments.
- Screen horizontal padding: 18-24pt.
- Sheet panel padding: 16-20pt.
- Control cluster spacing: 12pt.
- Remote deck radius: 36pt.
- Sheet panel radius: 26-28pt.
- Minimum tap target: 44pt.

## Rules

- Use SF Symbols for functional icons.
- Do not use emoji as icons.
- Do not use purple-to-blue gradient backgrounds.
- Do not use default blue tint as the app identity.
- Keep Liquid Glass on floating controls and navigation, not as a content-layer wash.
- Tint only primary actions or active feedback; repeated controls should stay mostly neutral glass.
- Keep network/protocol claims out of decorative UI copy unless backed by validation evidence.
