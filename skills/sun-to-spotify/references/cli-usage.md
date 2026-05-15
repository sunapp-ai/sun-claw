# SUN CLI Usage Reference

This reference gives Hermes-safe guidance for using the SUN CLI with the `sun-to-spotify` skill.

For installation and full developer documentation, use the official project repository:

https://github.com/sunapp-ai/sun-to-spotify

## What the CLI Does

The SUN CLI lets users generate audio courses from:

- a topic
- a prompt
- a document
- a local file
- a set of notes or research material

The skill should use the SUN CLI whenever it is available.

## Installation Guidance

If the SUN CLI is not installed, direct the user to the official installation instructions in the project repository:

https://github.com/sunapp-ai/sun-to-spotify

Do not ask users to paste secrets into the conversation.

Do not print authentication tokens, API keys, or private credentials.

## Basic Usage Flow

When helping a user, the skill should:

1. Confirm the user has installed the SUN CLI.
2. Confirm the user is signed in or authenticated through the official SUN flow.
3. Ask what they want to turn into an audio course.
4. Help them provide the topic, prompt, document, or file.
5. Start the course generation flow through the SUN CLI.
6. Monitor the generation status.
7. Return the final course result or next step.

## Troubleshooting

If the SUN CLI command is unavailable, ask the user to confirm that installation was completed using the official repository instructions.

If authentication fails, ask the user to sign in again through the official SUN flow.

If course generation fails, explain the error in plain language and ask whether they want to try again with a shorter or clearer input.

## Security Notes

The skill should not expose secrets, tokens, private credentials, or raw authenticated request examples.

The skill should direct users to the official project repository for installation details instead of embedding installer commands inside Hermes.
