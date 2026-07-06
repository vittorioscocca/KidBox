One-line: The tinted Home-grid category tile — icon, title, subtitle, optional red badge, in the category's color.

```jsx
<HomeCard title="Calendario" subtitle="Eventi e affidamenti"
          tint="var(--kb-cat-purple)" icon={<Calendar/>} badge={2}
          onClick={openCalendar} />
```

Fills its `tint` at 10%, borders at 18%, radius 16, min-height 120. `badge` shows the red count; `locked` shows a lock glyph for gated features. Lay them out in a 2-col grid with 12px gap (the real Home layout).
