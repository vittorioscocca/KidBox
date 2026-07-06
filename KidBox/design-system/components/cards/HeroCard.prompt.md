One-line: The family-photo hero at the top of Home — full-bleed image, protection gradient, overlaid date/badge/title and a "change photo" affordance.

```jsx
<HeroCard title="Famiglia Scocca" dateText="lunedì 6 luglio"
          badgeText="3 membri" photo={photoUrl} onClick={pickPhoto} />
```

Omit `photo` for the warm orange-gradient placeholder. `height` defaults to 300. Text sits on a bottom-up dark protection gradient so it stays legible on any image.
