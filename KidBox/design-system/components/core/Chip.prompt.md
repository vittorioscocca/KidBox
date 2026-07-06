One-line: Rounded pill for visibility tags, feature tags and filters — neutral or category-tinted.

```jsx
<Chip>Tutta la famiglia</Chip>
<Chip variant="tinted" tint="var(--kb-cat-green)">Sincronizzato</Chip>
```

`variant="tinted"` needs a `tint` (a `--kb-cat-*` token or hex) and renders a soft 14% fill + 26% border in that color. Default is the neutral chip surface.
