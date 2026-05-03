# User Stories

## Subtitle & Word Saving (Chrome Extension)

### S1: Real-time subtitle display
- **As a** Learner, **I want to** see English subtitles in real-time while watching Netflix/YouTube, **so that** I can check parts I couldn't hear.
- **Acceptance criteria**: Subtitles extracted from DOM and displayed in extension UI.
- **Priority**: Must-have | **Complexity**: L

### S2: Word meaning popup
- **As a** Learner, **I want to** click a word in subtitles to see its meaning, **so that** I can look up words without stopping the video.
- **Acceptance criteria**: Click → popup with meaning displayed within 100ms.
- **Priority**: Must-have | **Complexity**: M

### S3: Save words/phrases
- **As a** Learner, **I want to** save words/phrases with one click, **so that** I can review them later.
- **Acceptance criteria**: Save button → synced to cloud → reflected in web app.
- **Priority**: Must-have | **Complexity**: M

## Shadowing (Chrome Extension)

### S4: Auto-pause per sentence
- **As a** Learner, **I want to** have the video auto-pause after each subtitle sentence, **so that** I have time to speak.
- **Acceptance criteria**: Shadowing mode ON → auto-pause at sentence end → resume with button/key.
- **Priority**: Must-have | **Complexity**: L

### S5: A-B repeat
- **As a** Learner, **I want to** loop a specific section of the video, **so that** I can practice parts I couldn't hear.
- **Acceptance criteria**: Set A and B points → loop playback between them.
- **Priority**: Must-have | **Complexity**: M

## Review (Web App)

### S6: Vocabulary list
- **As a** Learner, **I want to** browse my saved words, **so that** I can review what I've learned.
- **Acceptance criteria**: Word list displayed, click to reveal meaning, search and filter.
- **Priority**: Must-have | **Complexity**: S

### S7: Quiz
- **As a** Learner, **I want to** take quizzes from my saved words, **so that** I can reinforce my memory.
- **Acceptance criteria**: Auto-generated quizzes (multiple choice, fill-in-the-blank), accuracy displayed.
- **Priority**: Must-have | **Complexity**: L

### S8: Spaced repetition
- **As a** Learner, **I want to** have review timing managed automatically, **so that** I can memorize efficiently following the forgetting curve.
- **Acceptance criteria**: Spaced repetition algorithm calculates next review date.
- **Priority**: Should-have | **Complexity**: M

## Authentication

### S9: Account management
- **As a** Learner, **I want to** create an account and log in, **so that** I can sync data across devices.
- **Acceptance criteria**: Cognito auth, sign-up/login/logout working.
- **Priority**: Must-have | **Complexity**: M
