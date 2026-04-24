#!/usr/bin/env zsh

claude --allowedTools "Read,Edit,Write,Bash,MultiEdit" "$(cat ResumeWorkPrompt.md)"
