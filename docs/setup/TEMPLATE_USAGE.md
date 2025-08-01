# CLAUDE.md Template Usage Guide

This template provides a comprehensive structure for setting up Claude Code guidance in any project. Here's how to use it effectively:

## Template Overview

The CLAUDE.md template is designed to:
- Provide immediate context to Claude Code about your project
- Establish consistent development patterns
- Document commands and workflows
- Create a memory bank system for AI context persistence

## How to Use This Template

### 1. Copy the Template
Copy CLAUDE.md to your project's root directory or `.claude/` folder.

### 2. Replace Placeholder Sections

#### Repository Overview
Replace `[Provide a clear, concise description...]` with:
- What your project does
- Who it's for
- Key features

Example:
```markdown
## Repository Overview
This is a React-based dashboard for monitoring IoT devices, providing real-time 
metrics visualization and alert management for enterprise customers.
```

#### High-Level Architecture
Replace the architecture placeholder with your actual system design:
```markdown
## High-Level Architecture
- **Frontend**: React 18 with TypeScript, Vite build system
- **Backend**: Node.js Express API with PostgreSQL
- **Infrastructure**: Docker containers deployed on AWS ECS
- **Data Flow**: IoT devices → MQTT broker → Backend API → Frontend WebSocket
```

#### Development Commands
Replace command placeholders like `[npm install | pip install...]` with your actual commands:
```markdown
### Setup and Installation
```bash
# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your configuration

# Initialize local development
docker-compose up -d
```

### 3. Memory Bank Structure

The template includes a sophisticated memory bank system in `.claude/memory-bank/`:

```
.claude/memory-bank/
├── core/              # Universal templates and policies
├── active/            # Current work context
├── sessions/          # Session management
├── decision_log/      # Historical decisions
├── cache/             # Local state files
└── generated/         # Auto-generated docs
```

This structure helps Claude Code:
- Remember context between sessions
- Track decisions and rationale
- Maintain project state
- Apply consistent governance

### 4. Customize Project Structure

Update the directory tree to match your project:
```
project-root/
├── .claude/                # Claude Code configuration
├── frontend/              # React application
├── backend/               # Express API
├── infrastructure/        # Terraform/Docker configs
└── scripts/              # Build and deployment scripts
```

### 5. Add Project-Specific Sections

Consider adding sections for:
- API documentation links
- Design system guidelines
- Release procedures
- Performance benchmarks
- Integration test scenarios

## Best Practices

1. **Keep Commands Real**: Only include commands that actually work in your project
2. **Be Specific**: Replace all placeholders with actual values
3. **Stay Current**: Update the file as your project evolves
4. **Include Examples**: Add real examples from your codebase
5. **Document Gotchas**: Include any non-obvious setup requirements

## Example Customizations

### For a Python Project
```markdown
### Development Workflow
```bash
# Start development server
python manage.py runserver

# Run tests
pytest

# Run specific test
pytest tests/test_api.py::test_user_creation

# Lint code
ruff check .

# Format code
black .
```

### For a Go Project
```markdown
### Development Workflow
```bash
# Start development server
go run cmd/server/main.go

# Run tests
go test ./...

# Run specific test
go test -run TestUserCreation ./internal/api

# Lint code
golangci-lint run

# Format code
go fmt ./...
```

## Memory Bank Usage

The memory bank system helps maintain context across Claude Code sessions:

1. **active/**: Keep current task status here
2. **decision_log/**: Document why you made specific choices
3. **cache/**: Store project state that needs quick access
4. **generated/**: Let Claude Code auto-generate analysis docs

## Quick Start Checklist

- [ ] Copy CLAUDE.md to your project
- [ ] Replace all placeholder text with real content
- [ ] Update command examples to match your tooling
- [ ] Customize the directory structure
- [ ] Add project-specific guidelines
- [ ] Set up the memory bank directories
- [ ] Test that all documented commands work

## Remember

This template is meant to be adapted. The goal is to create a living document that makes it easy for Claude Code to understand and work with your specific project effectively.