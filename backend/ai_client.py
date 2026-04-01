"""AI client using OpenAI-compatible API."""
import os
from openai import OpenAI
from dotenv import load_dotenv
from backend.database import get_setting

load_dotenv()

# --- System Prompts ---

DEFAULT_SYSTEM_PROMPT = """你是 Studorge 智能学习助手，一位耐心且富有洞察力的导师。

你的核心职责：
- 帮助用户深入理解知识，而不仅仅是给出答案
- 用循序渐进的方式解释复杂概念，从直觉出发，再到严谨定义
- 善用类比和生活中的例子来降低理解门槛
- 对于关键概念，先给出一句话总结，再展开详细解释

回答格式要求：
- 使用清晰的层级结构（标题、小标题、列表）组织内容
- 数学公式使用 LaTeX：行内公式用 $...$，独立公式用 $$...$$
- 代码使用 markdown 代码块并标注语言
- 重要术语首次出现时加粗并给出简要定义
- 适当使用表格对比相似概念的异同

教学策略：
- 先回答「是什么」，再解释「为什么」，最后说明「怎么用」
- 如果问题涉及多个层次，主动拆解并逐层深入
- 在回答末尾，可以提示用户可以进一步探索的方向

使用与用户相同的语言回答。"""

RAG_SYSTEM_PROMPT = """你是 Studorge 智能学习助手。用户之前已经学习过一些相关内容（见下方参考资料）。

你的任务：
- 基于用户之前的学习内容，给出连贯的回答
- 如果新问题与之前学过的内容有关联，主动建立知识之间的联系
- 避免重复用户已经掌握的基础内容，在已有基础上深入
- 如果参考资料中有相关内容，自然地引用并扩展

回答格式要求：
- 使用清晰的层级结构组织内容
- 数学公式使用 LaTeX：行内公式用 $...$，独立公式用 $$...$$
- 代码使用 markdown 代码块并标注语言
- 重要术语加粗

使用与用户相同的语言回答。"""


def get_ai_client():
    api_key = get_setting("api_key") or os.getenv("OPENAI_API_KEY")
    base_url = get_setting("api_base_url") or os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
    return OpenAI(api_key=api_key, base_url=base_url)


def get_model():
    return get_setting("api_model") or os.getenv("OPENAI_MODEL", "gpt-4o")


def _build_messages(
    question: str,
    context: str = "",
    system_prompt: str = "",
    image_data_url: str | None = None,
) -> list:
    messages = [{"role": "system", "content": system_prompt or DEFAULT_SYSTEM_PROMPT}]
    if context:
        messages.append({
            "role": "system",
            "content": f"以下是用户之前学习过的相关内容：\n{context}",
        })
    if image_data_url:
        messages.append({
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": image_data_url, "detail": "high"}},
                {"type": "text", "text": question},
            ],
        })
    else:
        messages.append({"role": "user", "content": question})
    return messages


RESPONSE_LENGTH_INSTRUCTIONS = {
    "normal": "【回答长度要求】请给出简洁精炼的回答，控制在150-250字以内。直接切入重点，省略铺垫和过多举例，不展开延伸内容。",
    "extend": "【回答长度要求】请给出适度展开的回答，大约400-700字。涵盖核心概念和必要的例子，但不需要面面俱到。",
    "extend_longer": "【回答长度要求】请给出详尽深入的回答，充分展开所有相关知识点，可以包含多个例子、类比、对比分析和延伸探讨，字数不限。",
}


def build_system_prompt(base_prompt: str, response_length: str) -> str:
    instruction = RESPONSE_LENGTH_INSTRUCTIONS.get(response_length, RESPONSE_LENGTH_INSTRUCTIONS["extend"])
    return f"{base_prompt}\n\n{instruction}"


def chat_with_ai(
    question: str,
    context: str = "",
    system_prompt: str = "",
    image_data_url: str | None = None,
    response_length: str = "extend",
) -> str:
    """Send a question to the AI and get a response."""
    client = get_ai_client()
    base = system_prompt or DEFAULT_SYSTEM_PROMPT
    messages = _build_messages(question, context, build_system_prompt(base, response_length), image_data_url)
    response = client.chat.completions.create(
        model=get_model(),
        messages=messages,
        temperature=0.7,
        max_completion_tokens=4096,
    )
    return response.choices[0].message.content


def chat_with_rag(
    question: str,
    rag_results: list[dict],
    image_data_url: str | None = None,
    response_length: str = "extend",
) -> str:
    """Chat with AI using RAG context."""
    context_parts = [item["document"] for item in rag_results]
    context = "\n---\n".join(context_parts) if context_parts else ""
    base = RAG_SYSTEM_PROMPT if context else DEFAULT_SYSTEM_PROMPT
    return chat_with_ai(
        question,
        context=context,
        system_prompt=base,
        image_data_url=image_data_url,
        response_length=response_length,
    )


def stream_chat_with_rag(
    question: str,
    rag_results: list[dict],
    image_data_url: str | None = None,
    response_length: str = "extend",
):
    """Stream AI response tokens using RAG context. Yields str chunks."""
    context_parts = [item["document"] for item in rag_results]
    context = "\n---\n".join(context_parts) if context_parts else ""
    base = RAG_SYSTEM_PROMPT if context else DEFAULT_SYSTEM_PROMPT

    client = get_ai_client()
    messages = _build_messages(
        question,
        context,
        build_system_prompt(base, response_length),
        image_data_url,
    )

    stream = client.chat.completions.create(
        model=get_model(),
        messages=messages,
        temperature=0.7,
        max_completion_tokens=4096,
        stream=True,
    )
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content


def generate_title(text: str) -> str:
    """Generate a concise title (≤10 Chinese chars) for the given text."""
    try:
        client = get_ai_client()
        response = client.chat.completions.create(
            model=get_model(),
            messages=[
                {"role": "system", "content": (
                    "为以下内容生成一个简洁标题，要求：\n"
                    "- 最多10个汉字（英文单词算一个词）\n"
                    "- 只输出标题本身，不加引号、标点或任何解释\n"
                    "- 抓住核心概念，言简意赅"
                )},
                {"role": "user", "content": text[:300]},
            ],
            max_completion_tokens=25,
            temperature=0.3,
        )
        return response.choices[0].message.content.strip()[:20]
    except Exception:
        # Fallback: first meaningful chunk of text
        return text[:15].strip()
