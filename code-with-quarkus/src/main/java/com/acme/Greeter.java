package com.acme;

import dev.langchain4j.service.SystemMessage;
import dev.langchain4j.service.UserMessage;
import io.quarkiverse.langchain4j.RegisterAiService;

/**
 * Greeter interface with a system prompt to introduce itself.
 */
@RegisterAiService
public interface Greeter {
    /**
     * Introduces the chat model to the user.
     *
     * @return the introduction message
     */
    @SystemMessage(
        { "You are a helpful AI assistant that introduces itself to users." }
    )
    @UserMessage({ "Please introduce yourself to the user." })
    String introduce();
}
