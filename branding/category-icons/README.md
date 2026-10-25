# Category icons

One icon per category, named by the category id (`mugs`, `mothers-day`, …, the ids in
`mobile/functions/scripts/seed-data/categories.ts`).

| Folder | What |
|---|---|
| `../GGimages/` | Original 3D renders (1254×1254 PNG, transparent), named by their image title |
| `./{id}.png` | 512×512 transparent PNG masters (resized from GGimages) |
| `./webp/{id}.webp` | 512×512 WebP, ~60 KB each — **these are what the app loads** |

Prompts used to generate the renders: `docs/design/category_icon_prompts.md`.

## Add or replace an icon

1. Put the new 512×512 transparent image in `webp/` as `{category id}.webp` (or `.png`).
   To convert from a big PNG:
   ```bash
   python3 -c "from PIL import Image; im=Image.open('IN.png').convert('RGBA').resize((512,512), Image.LANCZOS); im.save('webp/ID.webp', quality=90, method=6, alpha_quality=95)"
   ```
2. Upload it and point the category at it (Storage `categories/{id}.webp`, `categories/{id}.iconUrl`, audit-log entry):
   ```bash
   cd mobile/functions
   npm run icons:categories -- --target=dev --only=ID --dry-run   # check first
   npm run icons:categories -- --target=dev --only=ID             # REAL project
   ```
   Without `--only` it uploads every file in `webp/`. Files whose name is not a category id are skipped.

A single icon can also be changed in the dashboard (Categories ▸ edit ▸ Icon). Re-running
`npm run seed:dev` keeps the uploaded icons.
