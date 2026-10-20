// Pure Native Client Bridge for Tauri-Lua (No mocks, no hardcoded stubs)

declare global {
  interface Window {
    __TAURI_RAW_INVOKE__?: (raw: string) => Promise<string>;
    __TAURI_TOKEN__?: string;
    __TAURI_CHANNELS__?: Record<number, any>;
    __TAURI_DISPATCH_CHANNEL__?: (id: number, data: any) => void;
    __TAURI__?: any;
  }
}

let channelSeq = 0;
const channelMap: Record<number, Channel> = {};

export class Channel {
  id: number;
  onmessage: ((data: any) => void) | null;

  constructor(onMessage?: (data: any) => void) {
    this.id = ++channelSeq;
    this.onmessage = onMessage || null;
    channelMap[this.id] = this;

    if (typeof window !== 'undefined') {
      window.__TAURI_CHANNELS__ = channelMap;
      window.__TAURI_DISPATCH_CHANNEL__ = (id: number, data: any) => {
        const ch = channelMap[id];
        if (ch && typeof ch.onmessage === 'function') {
          ch.onmessage(data);
        }
      };
    }
  }

  send(data: any) {
    if (typeof this.onmessage === 'function') {
      this.onmessage(data);
    }
  }

  close() {
    delete channelMap[this.id];
  }

  toJSON() {
    return { __tauri_channel__: this.id };
  }
}

export async function invoke<T = any>(cmd: string, args: Record<string, any> = {}): Promise<T> {
  const win = typeof window !== 'undefined' ? (window as any) : null;

  // 1. Direct native bridge invocation (WKWebView / WebView2)
  if (win && typeof win.__TAURI_RAW_INVOKE__ === 'function') {
    const token = win.__TAURI_TOKEN__ || '';
    const raw = JSON.stringify([cmd, args, token]);
    const resStr = await win.__TAURI_RAW_INVOKE__(raw);
    const parsed = typeof resStr === 'string' ? JSON.parse(resStr) : resStr;

    if (parsed && typeof parsed === 'object') {
      if (parsed.error) {
        throw new Error(parsed.error);
      }
      if ('data' in parsed) {
        return parsed.data as T;
      }
      if (Object.keys(parsed).length === 0) {
        return null as unknown as T;
      }
    }
    return parsed as T;
  }

  // 2. High-level runtime fallback if injected
  if (win && win.__TAURI__ && typeof win.__TAURI__.invoke === 'function') {
    return win.__TAURI__.invoke(cmd, args);
  }

  throw new Error('Tauri-Lua runtime not detected. This function requires the native desktop application.');
}

if (typeof window !== 'undefined') {
  window.__TAURI__ = window.__TAURI__ || {
    invoke,
    Channel,
    core: { invoke }
  };
}
