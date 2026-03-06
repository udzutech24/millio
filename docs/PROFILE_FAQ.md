# Profile FAQ

## What was added
- Settings now includes an `FAQ` item in Profile.
- FAQ includes:
  - a list screen with sections and clickable questions
  - a detail screen with question and answer text
- Base content is provided in English and Russian.

## Files
- `millio/UI/Profile/ProfileFAQModels.swift`
- `millio/UI/Profile/ProfileFAQView.swift`
- `millio/UI/Profile/ProfileView.swift`

## How to update FAQ content
1. Open `ProfileFAQModels.swift`.
2. Edit `englishSections` and `russianSections`.
3. Keep `id` values stable and unique in each language set.
4. Each item must include:
   - question
   - at least one paragraph in `answerParagraphs`
   - optional `note`
