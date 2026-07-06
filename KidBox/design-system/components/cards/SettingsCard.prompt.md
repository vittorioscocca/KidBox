One-line: The Settings list-row card — leading tinted icon, title + subtitle, optional trailing control.

```jsx
<SettingsCard title="Aspetto" subtitle="Chiaro, scuro o sistema"
              tone="primary" icon={<Sun/>}
              trailing={<Chevron/>} onClick={open} />
```

`tone`: primary (orange) | secondary | info | warning | danger — sets the icon color and border tint. Pass `children` to render extra content inside the same visual group (e.g. an inline control).
