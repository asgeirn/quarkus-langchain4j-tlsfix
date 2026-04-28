#!/bin/bash

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY environment variable is not set."
    exit 1
fi

# Test the OpenAI API endpoint configured by Quarkus
curl -v --cacert rootCA.pem \
  https://127.0.0.1:10443/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "system", "content": "You are a helpful AI assistant that introduces itself to users."},
      {"role": "user", "content": "Please introduce yourself to the user."}
    ]
  }'
