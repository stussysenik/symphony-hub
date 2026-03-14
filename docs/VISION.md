# Vision: Using Visual Assets with Symphony Agents

> Guide to making Symphony agents SEE mockups, screenshots, and designs.
> Visual context dramatically improves agent output for UI implementation tasks.

---

## Why Vision Matters

Without vision, agents implement UI tasks blind:
- They read "match the mockup" but can't see the mockup
- They guess at colors, spacing, and layout
- Multiple iteration cycles: implement → review → fix → review

With vision, agents see what they're building:
- Mockup images are sent alongside the text prompt
- Agents analyze layouts, colors, and components before writing code
- First implementation is much closer to the design intent

---

## How It Works

### Data Flow

```
Linear Issue (with image attachments)
    │
    ▼
AssetCollector
    │ Gathers images from:
    │ 1. Linear attachments (.png, .jpg, .gif, .webp, .svg, Figma links)
    │ 2. Project design directories (design/, assets/, mockups/, screenshots/)
    │
    ▼
AssetCache
    │ Downloads remote images to workspace/assets/
    │ Writes manifest.json with metadata
    │
    ▼
PromptBuilder
    │ Adds "Visual Context" section to the agent prompt
    │ Lists all available visual assets
    │
    ▼
AppServer (multimodal input)
    │ Sends text + image blocks to Codex
    │ Agent receives both the prompt AND the images
    │
    ▼
Agent sees mockups and implements accordingly
```

### Automatic Collection

Visual assets are collected automatically on the first turn of each agent run.
No manual configuration needed — if images exist, they'll be found and passed.

**Sources checked:**
1. **Linear attachments** — Any image attached to the Linear issue
2. **Project directories** — Files in `design/`, `assets/`, `mockups/`, `screenshots/` within the workspace

---

## Attaching Mockups to Linear Issues

### Best Practices

1. **Attach directly to the issue** — Drag and drop images into the Linear issue description or comments

2. **Name your files descriptively:**
   - `homepage-hero.png` (not `screenshot-2024-01-15.png`)
   - `login-form-mobile.png` (not `image.png`)
   - `settings-dark-mode.png` (not `untitled.png`)

3. **Include multiple views if relevant:**
   - Desktop and mobile versions
   - Light and dark mode
   - Different states (empty, loading, error, populated)

4. **Reference in the description:**
   ```
   Title: Implement settings page

   Description:
   Build the settings page matching the attached mockup.
   - See "settings-desktop.png" for the desktop layout
   - See "settings-mobile.png" for the mobile layout
   - Use the color palette from the design system
   ```

### Supported Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| PNG | `.png` | Best for screenshots and UI mockups |
| JPEG | `.jpg`, `.jpeg` | Good for photos, smaller file size |
| GIF | `.gif` | Animated UI interactions |
| WebP | `.webp` | Modern format, smaller files |
| SVG | `.svg` | Vector graphics, icons |
| Figma | `figma.com` links | Detected by URL pattern |

---

## Configuration

### Per-Project Assets Config

In `projects.yml`, each project can configure asset handling:

```yaml
projects:
  - name: "my-project"
    assets:
      collect_attachments: true      # Fetch images from Linear attachments
      scan_project_dirs: true        # Scan design/ assets/ dirs in workspace
      capture_screenshots: false     # Future: auto-screenshot running app
      supported_formats:
        - png
        - jpg
        - gif
        - webp
        - svg
        - figma
```

### Environment Variables

```bash
# Required for basic vision (Linear attachments)
LINEAR_API_KEY=lin_api_xxx

# Optional: enables Figma MCP integration
FIGMA_ACCESS_TOKEN=xxx
```

---

## Screenshot Comparison Tool

Agents can use the `compare_screenshots` dynamic tool to verify their
implementation matches the mockup:

```
Agent calls: compare_screenshots
  implementation_path: "screenshots/my-implementation.png"
  mockup_id: "abc123"

Response: Both files available. Compare visually and list differences.
```

This is a self-check mechanism — the agent takes a screenshot of its work
and compares it against the original mockup.

---

## Figma MCP Integration

For deeper design integration, configure the Figma MCP server:

1. Add `FIGMA_ACCESS_TOKEN` to `.env.local`
2. Reference `figma-mcp.json` in your Codex/Claude config
3. Agents can then query Figma files for:
   - Design tokens (colors, typography, spacing)
   - Component properties and variants
   - Layout measurements
   - Auto-layout settings

See `SETUP.md` for detailed Figma setup instructions.

---

## Troubleshooting

### "No visual assets found"

**Check:**
- Does the Linear issue have image attachments?
- Are the attachments in a supported format? (png, jpg, gif, webp, svg)
- Does the workspace have design directories with images?

### "Failed to download asset"

**Check:**
- Is the Linear API key valid?
- Can the workspace access the internet?
- Are Linear attachment URLs still valid? (they may expire)

### "Agent ignores the mockup"

**Try:**
- Make the description more explicit: "You MUST match the attached mockup"
- Attach fewer images (too many can dilute focus)
- Name images descriptively so the agent knows which is which

---

## Architecture Details

For the full technical architecture, see:
- `docs/ARCHITECTURE.md` — Vision data flow diagrams
- `asset_collector.ex` — Source code for asset collection
- `asset_cache.ex` — Source code for caching and manifest
- `prompt_builder.ex` — How visual context is added to prompts
- `app_server.ex` — How multimodal input is built
