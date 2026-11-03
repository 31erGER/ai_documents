# most important commands

/login: login
STRG + T: toggle thinking box


# project setup


### Project .pi directory

.pi/settings.json 	Project-level settings, resource paths, and Pi package declarations.
.pi/mcp.json 	Project MCP servers.
.pi/SYSTEM.md 	Replaces the system prompt for the project.
.pi/APPEND_SYSTEM.md 	Adds project-specific instructions to the system prompt.
.pi/extensions/ 	Project extensions.
.pi/skills/ 	Project skills and supporting files.
.pi/prompts/ 	Project prompt templates exposed as slash commands.
.pi/themes/ 	Project theme files.

For SYSTEM.md and APPEND_SYSTEM.md, the trusted project file takes precedence over the corresponding agent-directory file. Files with the same name are not combined.
