# SUN HTTP API Reference

This reference describes the public SUN API at a high level for Hermes publishing.

The API is used by the SUN CLI to create and manage audio course jobs. The skill should prefer the official SUN CLI flow whenever possible.

## API Overview

The public API supports:

- Checking identity and authentication status
- Creating audio course generation jobs
- Checking course generation status
- Retrieving generated course outputs
- Managing authenticated user requests

All public API endpoints use versioned public routes and exchange JSON request and response bodies encoded as UTF-8.

## Authentication

Some API actions require authentication through the official SUN authentication flow.

Do not ask users to paste secrets directly into prompts.

Do not print or expose tokens in terminal output, logs, generated files, or shared messages.

If authentication is missing or invalid, ask the user to sign in through the official SUN CLI or official SUN app flow.

## Expected Skill Behavior

When using the HTTP API indirectly through the SUN CLI, the skill should:

1. Confirm the user has the SUN CLI installed.
2. Confirm the user is authenticated.
3. Ask the user what topic, prompt, document, or file they want converted into an audio course.
4. Start the audio course generation flow.
5. Monitor the course job until it completes.
6. Return the final result or next action clearly.

## Error Handling

If an API request fails, the skill should explain the issue in plain language.

Common cases include:

- The user is not authenticated.
- The input topic or file is missing.
- The course generation job is still processing.
- The course generation job failed.
- The configured SUN service endpoint is unavailable.

## Security Notes

The skill should not collect, display, store, or transmit user secrets outside the official SUN authentication flow.

The skill should not include hardcoded tokens, example bearer tokens, or shell commands that expose credentials.

