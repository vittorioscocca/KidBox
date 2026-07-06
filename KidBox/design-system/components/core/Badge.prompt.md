One-line: Small red count badge overlaid on Home cards and tab items.

```jsx
<div style={{position:'relative'}}>
  <HomeCard .../>
  <span style={{position:'absolute',top:8,right:8}}><Badge count={3}/></span>
</div>
```

Circle under 10, capsule at 10+. `count` of 0 renders nothing. `tone`: danger (default) | orange | green | blue.
