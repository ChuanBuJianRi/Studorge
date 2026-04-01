# Effstudy

基于 **FastAPI** 与 **OpenAI 兼容 API** 的本地智能学习工作台：用专题与树状节点组织问答，结合 **ChromaDB** 做按专题的 **RAG 检索**，支持流式输出、文件导入、语音转写与 TTS。

## 功能概览

| 能力 | 说明 |
|------|------|
| 专题与子专题 | 多层级主题，可从某条问答「深挖」新建子专题 |
| 树状学习节点 | 问答以父子节点组织，可生成简短标题便于浏览 |
| RAG | 将历史问答写入向量库，新提问时自动检索相关上下文 |
| 流式回答 | SSE 流式输出，结束后写入数据库并更新向量索引 |
| 多模态与媒体 | 支持图片（vision）输入；上传 PDF / 文本提取正文；Whisper 转写；OpenAI TTS 朗读 |
| API 配置 | 环境变量或应用内设置（密钥仅存本地 SQLite，**勿提交仓库**） |

## 技术栈

- **后端**：Python 3、FastAPI、Uvicorn、SQLite（`data/learning.db`）、ChromaDB（`data/chroma_db`）
- **AI**：`openai` 官方 SDK（兼容自定义 `base_url` / 模型名）
- **前端**：静态页面（由 FastAPI 挂载 `frontend/`）

## 快速开始

### 1. 克隆与依赖

```bash
git clone https://github.com/ChuanBuJianRi/Effstudy.git
cd Effstudy
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. 配置 API（不要提交密钥）

复制示例环境文件并编辑：

```bash
cp .env.example .env
```

在 `.env` 中填写（也可在网页「设置」里配置，会写入本地数据库）：

- `OPENAI_API_KEY`：API 密钥  
- `OPENAI_BASE_URL`：例如 `https://api.openai.com/v1` 或其它兼容端点  
- `OPENAI_MODEL`：例如 `gpt-4o`  

**安全提示**

- 仓库已 `.gitignore` 忽略 `.env`、`data/` 等；请勿将含真实密钥的 `.env` 或数据库目录提交到 Git。  
- 若曾误提交密钥，请在服务商控制台**轮换密钥**，并从 Git 历史中清理敏感文件。

### 3. 启动

在项目根目录执行：

```bash
python run.py
```

浏览器访问：<http://127.0.0.1:8000/>

## 项目结构

```
Effstudy/
├── backend/           # FastAPI 应用、数据库、RAG、AI 客户端
├── frontend/          # 静态前端（index.html 等）
├── data/              # 本地生成：SQLite + Chroma（默认已忽略，不进入版本库）
├── run.py             # 启动入口
├── requirements.txt
├── .env.example       # 环境变量模板（无真实密钥）
└── README.md
```

## 常用 API（节选）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | 前端页面 |
| GET/POST | `/api/topics` | 专题列表与创建 |
| POST | `/api/ask`、`/api/ask/stream` | 提问（普通 / 流式） |
| GET | `/api/topics/{id}/tree`、`/full-tree` | 专题节点树 |
| POST | `/api/upload` | PDF / 文本上传提取 |
| POST | `/api/transcribe` | 语音转文字 |
| POST | `/api/tts` | 文字转语音 |
| GET/POST | `/api/settings` | 读取 / 更新 API 相关设置 |

## 许可证

若未另行指定，以仓库内许可证文件为准；若无许可证文件，使用前请与作者确认。

## 贡献与反馈

欢迎通过 Issue / Pull Request 交流。提交代码前请确认未包含 `.env`、`data/` 或个人密钥。
