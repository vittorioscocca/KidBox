One-line: The KidBox button — ink-filled primary by default, with an orange-gradient `ai` variant for the "Chiedi all'AI" call-to-action.

```jsx
<Button variant="primary">Continua</Button>
<Button variant="ai" icon={<Sparkles/>}>Chiedi all'AI</Button>
<Button variant="secondary" size="sm">Annulla</Button>
```

Variants: `primary` (ink, mirrors LoginView), `accent` (brand orange), `ai` (gradient FAB-style), `secondary` (bordered pill), `ghost`, `danger`. Sizes `sm | md | lg`. Pills by default. Pass `icon` / `iconRight` as glyph nodes, `fullWidth` for forms.
