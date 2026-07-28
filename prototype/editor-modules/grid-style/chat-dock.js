export function appendChatMessage(messagesNode, role, text) {
  if (!messagesNode || !text) {
    return null;
  }

  const node = messagesNode.ownerDocument.createElement("div");
  node.className = `grid-chat-message is-${role}`;
  node.textContent = text;
  messagesNode.appendChild(node);
  messagesNode.scrollTop = messagesNode.scrollHeight;
  return node;
}

export function readChatInput(inputNode) {
  if (!inputNode) {
    return "";
  }

  const value = inputNode.value.trim();
  inputNode.value = "";
  return value;
}

export function bindChatDockEvents(refs, { onSend, onCollapse }) {
  refs.chatSendButton?.addEventListener("click", () => {
    onSend?.();
  });

  refs.chatDockCollapseButton?.addEventListener("click", () => {
    onCollapse?.();
  });

  refs.chatInput?.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) {
      return;
    }

    event.preventDefault();
    onSend?.();
  });
}
