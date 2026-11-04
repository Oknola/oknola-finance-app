# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class UserMessageTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:one)
  end

  test "requests assistant response after creation" do
    @chat.expects(:ask_assistant_later).once

    message = UserMessage.create!(chat: @chat, content: "Hello from user", ai_model: "gpt-4.1")
    message.update!(content: "updated")

    streams = capture_turbo_stream_broadcasts(@chat)
    assert_equal 2, streams.size
    assert_equal "append", streams.first["action"]
    assert_equal @chat.messages_target, streams.first["target"]
    assert_equal "update", streams.last["action"]
    assert_equal "user_message_#{message.id}", streams.last["target"]
  end

  test "allows user messages up to 4,000 characters" do
    message = UserMessage.new(chat: @chat, content: "a" * 4_000, ai_model: Chat.default_model)

    assert_predicate message, :valid?
  end

  test "rejects user messages longer than 4,000 characters" do
    message = UserMessage.new(chat: @chat, content: "a" * 4_001, ai_model: Chat.default_model)

    assert_not message.valid?
    assert_includes message.errors[:content], I18n.t("chats.message_too_long")
  end
end
