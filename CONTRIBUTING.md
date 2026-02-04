# Contributing to KidBox

This repository is private and currently maintained by a small team.

## Branching strategy

- `main`: stable branch, always deployable
- `develop`: active development branch

### Feature branches
Create feature branches from `develop` using the following naming:

- `feature/<short-description>`
- `fix/<short-description>`
- `chore/<short-description>`

Example:
feature/home-today-card
fix/routine-check-sync

## Commits

Use clear, imperative commit messages:

- `Add today summary card`
- `Fix routine check duplication`
- `Refactor sync engine retry logic`

Avoid:
- vague messages (`update`, `fix stuff`)
- multiple unrelated changes in one commit

## Pull Requests

- Keep PRs small and focused
- Reference the related issue in the PR description
- Ensure the app builds before opening a PR

## Code style

- SwiftUI-first
- MVVM light (View + ViewModel + Services)
- Prefer clarity over cleverness
