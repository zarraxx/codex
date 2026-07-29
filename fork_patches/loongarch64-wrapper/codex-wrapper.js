#!/usr/bin/env node
"use strict";

// Local launcher/updater for zarraxx/codex LoongArch64 release builds.

const { createHash } = require("node:crypto");
const { createReadStream, createWriteStream } = require("node:fs");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline/promises");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const { spawn, spawnSync } = require("node:child_process");

const REPOSITORY = "zarraxx/codex";
const API_URL = `https://api.github.com/repos/${REPOSITORY}/releases?per_page=20`;
const TARGET = "loongarch64-unknown-linux-gnu";
const ARCHIVE_NAME = `codex-${TARGET}-release.tar.xz`;
const CHECKSUM_NAME = `${ARCHIVE_NAME}.sha256`;
const INSTALL_DIR = path.join(os.homedir(), "opt", "codex");
const BINARY_PATH = path.join(INSTALL_DIR, "bin", "codex");
const PREVIOUS_DIR = path.join(os.homedir(), "opt", "codex.previous");
const STATE_DIR = path.join(os.homedir(), ".cache", "codex-fork-wrapper");
const STATE_FILE = path.join(STATE_DIR, "update-state.json");
const LOCK_FILE = path.join(STATE_DIR, "update.lock");
const USER_AGENT = "zarraxx-codex-local-wrapper/1";
const WRAPPER_VERSION = "1.0.0";

function versionFromText(text) {
  const match = String(text).match(
    /(?:^|[^0-9A-Za-z])v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)(?=$|[^0-9A-Za-z])/,
  );
  return match?.[1] ?? null;
}

function versionParts(version) {
  return version
    .split(/[.+-]/, 3)
    .map((part) => Number.parseInt(part, 10) || 0);
}

function compareVersions(left, right) {
  const a = versionParts(left);
  const b = versionParts(right);
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] < b[index] ? -1 : 1;
  }
  return 0;
}

function localDateKey() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function readInstalledVersion() {
  const result = spawnSync(BINARY_PATH, ["--version"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  if (result.error || result.status !== 0) return null;
  return versionFromText(`${result.stdout}\n${result.stderr}`);
}

async function readState() {
  try {
    return JSON.parse(await fs.readFile(STATE_FILE, "utf8"));
  } catch {
    return {};
  }
}

async function writeState(extra = {}) {
  await fs.mkdir(STATE_DIR, { recursive: true });
  const state = {
    ...(await readState()),
    lastCheckDate: localDateKey(),
    lastCheckAt: new Date().toISOString(),
    ...extra,
  };
  const temporary = `${STATE_FILE}.${process.pid}.tmp`;
  await fs.writeFile(temporary, `${JSON.stringify(state, null, 2)}\n`, {
    mode: 0o600,
  });
  await fs.rename(temporary, STATE_FILE);
}

async function fetchResponse(url, timeout = 8_000) {
  const response = await fetch(url, {
    headers: {
      "Accept": "application/vnd.github+json",
      "User-Agent": USER_AGENT,
      "X-GitHub-Api-Version": "2022-11-28",
    },
    redirect: "follow",
    signal: AbortSignal.timeout(timeout),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }
  return response;
}

async function latestCompatibleRelease() {
  const response = await fetchResponse(API_URL);
  const releases = await response.json();
  const compatible = [];

  for (const release of releases) {
    if (release.draft || release.prerelease) continue;
    const version = versionFromText(release.tag_name);
    const archive = release.assets?.find(
      (asset) => asset.name === ARCHIVE_NAME,
    );
    const checksum = release.assets?.find(
      (asset) => asset.name === CHECKSUM_NAME,
    );
    if (version && archive && checksum) {
      compatible.push({
        version,
        tag: release.tag_name,
        archiveUrl: archive.browser_download_url,
        checksumUrl: checksum.browser_download_url,
      });
    }
  }

  compatible.sort((a, b) => compareVersions(b.version, a.version));
  if (!compatible[0]) {
    throw new Error(`最近的 Release 中没有 ${ARCHIVE_NAME}`);
  }
  return compatible[0];
}

async function acquireCheckLock() {
  await fs.mkdir(STATE_DIR, { recursive: true });
  try {
    const handle = await fs.open(LOCK_FILE, "wx", 0o600);
    await handle.writeFile(`${process.pid}\n`);
    await handle.close();
    return true;
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    try {
      const stat = await fs.stat(LOCK_FILE);
      if (Date.now() - stat.mtimeMs > 10 * 60 * 1000) {
        await fs.unlink(LOCK_FILE);
        return acquireCheckLock();
      }
    } catch {
      return acquireCheckLock();
    }
    return false;
  }
}

async function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, options);
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) reject(new Error(`${command} 被 ${signal} 终止`));
      else if (code !== 0) reject(new Error(`${command} 退出码为 ${code}`));
      else resolve();
    });
  });
}

async function download(url, destination) {
  const response = await fetchResponse(url, 120_000);
  if (!response.body) throw new Error("下载响应为空");
  await pipeline(
    Readable.fromWeb(response.body),
    createWriteStream(destination, { mode: 0o600 }),
  );
}

async function sha256(file) {
  const hash = createHash("sha256");
  const input = createReadStream(file);
  for await (const chunk of input) hash.update(chunk);
  return hash.digest("hex");
}

async function installRelease(release) {
  const optDir = path.dirname(INSTALL_DIR);
  await fs.mkdir(optDir, { recursive: true });
  const workDir = await fs.mkdtemp(path.join(optDir, ".codex-update-"));
  const archivePath = path.join(workDir, ARCHIVE_NAME);
  const stagedDir = path.join(workDir, "staged");
  const nextDir = path.join(optDir, `.codex-next-${process.pid}-${Date.now()}`);
  let movedCurrent = false;

  try {
    process.stderr.write(`[codex] 正在下载 ${release.tag}…\n`);
    const [checksumText] = await Promise.all([
      fetchResponse(release.checksumUrl, 30_000).then((response) =>
        response.text(),
      ),
      download(release.archiveUrl, archivePath),
    ]);
    const expected = checksumText
      .match(/\b[0-9a-fA-F]{64}\b/)?.[0]
      ?.toLowerCase();
    if (!expected) throw new Error("Release 校验文件格式无效");
    const actual = await sha256(archivePath);
    if (actual !== expected)
      throw new Error(`SHA-256 不匹配：期望 ${expected}，实际 ${actual}`);

    await fs.mkdir(stagedDir);
    await run(
      "tar",
      ["-xJf", archivePath, "-C", stagedDir, "--strip-components=1"],
      {
        stdio: "inherit",
      },
    );

    const stagedBinary = path.join(stagedDir, "bin", "codex");
    await fs.chmod(stagedBinary, 0o755);
    const probe = spawnSync(stagedBinary, ["--version"], {
      encoding: "utf8",
      timeout: 15_000,
    });
    const stagedVersion = versionFromText(
      `${probe.stdout ?? ""}\n${probe.stderr ?? ""}`,
    );
    if (
      probe.error ||
      probe.status !== 0 ||
      stagedVersion !== release.version
    ) {
      throw new Error(
        `新二进制试运行失败（期望 ${release.version}，得到 ${stagedVersion ?? "未知"}）`,
      );
    }

    await fs.rename(stagedDir, nextDir);
    await fs.rm(PREVIOUS_DIR, { recursive: true, force: true });
    try {
      await fs.rename(INSTALL_DIR, PREVIOUS_DIR);
      movedCurrent = true;
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    await fs.rename(nextDir, INSTALL_DIR);
    movedCurrent = false;
    process.stderr.write(
      `[codex] 已升级到 ${release.version}；上一版本保存在 ${PREVIOUS_DIR}\n`,
    );
  } catch (error) {
    if (movedCurrent) {
      try {
        await fs.rename(PREVIOUS_DIR, INSTALL_DIR);
        movedCurrent = false;
      } catch (rollbackError) {
        error.message += `；自动回退也失败：${rollbackError.message}`;
      }
    }
    throw error;
  } finally {
    await fs.rm(workDir, { recursive: true, force: true }).catch(() => {});
    await fs.rm(nextDir, { recursive: true, force: true }).catch(() => {});
  }
}

async function askToUpdate(installed, release) {
  process.stderr.write(
    `\n[codex] 发现 fork 新版本：${installed ?? "未安装"} → ${release.version} (${release.tag})\n`,
  );
  const terminal = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
  });
  try {
    const answer = await terminal.question(
      "现在下载、校验并替换 ~/opt/codex 吗？[y/N] ",
    );
    return /^(y|yes|是)$/i.test(answer.trim());
  } finally {
    terminal.close();
  }
}

async function checkForUpdate({
  force = false,
  assumeYes = false,
  failOnError = false,
} = {}) {
  if (!force && process.env.CODEX_WRAPPER_SKIP_UPDATE === "1") return;
  if (!force && (!process.stdin.isTTY || !process.stderr.isTTY)) return;

  const state = await readState();
  if (!force && state.lastCheckDate === localDateKey()) return;
  if (!(await acquireCheckLock())) {
    if (failOnError) throw new Error("另一个 Codex 更新进程正在运行");
    return;
  }

  try {
    const installed = readInstalledVersion();
    const release = await latestCompatibleRelease();
    const newer = !installed || compareVersions(installed, release.version) < 0;
    let outcome = "up-to-date";

    if (newer) {
      outcome = "declined";
      if (assumeYes || (await askToUpdate(installed, release))) {
        await installRelease(release);
        outcome = "updated";
      }
    } else if (force) {
      process.stderr.write(
        `[codex] 已是最新兼容版本 ${installed} (${release.tag})\n`,
      );
    }

    await writeState({
      installedVersion: readInstalledVersion(),
      latestVersion: release.version,
      latestTag: release.tag,
      outcome,
    });
  } catch (error) {
    await writeState({ outcome: "error", error: error.message }).catch(
      () => {},
    );
    if (failOnError) throw error;
    process.stderr.write(
      `[codex] 更新检查失败，继续使用当前版本：${error.message}\n`,
    );
  } finally {
    await fs.unlink(LOCK_FILE).catch(() => {});
  }
}

async function showStatus() {
  const installed = readInstalledVersion();
  process.stdout.write(`包装器: ${WRAPPER_VERSION} (${process.argv[1]})\n`);
  process.stdout.write(`原生程序: ${BINARY_PATH}\n`);
  process.stdout.write(`当前版本: ${installed ?? "不可用"}\n`);
  try {
    const release = await latestCompatibleRelease();
    process.stdout.write(`远端版本: ${release.version} (${release.tag})\n`);
    process.stdout.write(
      `状态: ${installed && compareVersions(installed, release.version) >= 0 ? "已是最新" : "可升级"}\n`,
    );
  } catch (error) {
    process.stdout.write(`远端版本: 查询失败（${error.message}）\n`);
  }
}

function launchCodex(args) {
  // This wrapper owns update checks, so suppress the native CLI's official
  // GitHub update prompt. A later user-provided -c value can still override it.
  const nativeArgs = ["-c", "check_for_update_on_startup=false", ...args];
  const child = spawn(BINARY_PATH, nativeArgs, {
    stdio: "inherit",
    env: process.env,
  });
  const forwardSignal = (signal) => {
    if (!child.killed) {
      try {
        child.kill(signal);
      } catch {
        /* child already exited */
      }
    }
  };
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.on(signal, () => forwardSignal(signal));
  }
  child.on("error", (error) => {
    process.stderr.write(`[codex] 无法启动 ${BINARY_PATH}：${error.message}\n`);
    process.exit(1);
  });
  child.on("exit", (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    else process.exit(code ?? 1);
  });
}

(async () => {
  if (process.platform !== "linux" || process.arch !== "loong64") {
    throw new Error(
      `此包装器只配置了 Linux loong64，当前为 ${process.platform} ${process.arch}`,
    );
  }

  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--wrapper-status") {
    await showStatus();
    return;
  }
  if (args[0] === "--wrapper-update" && args.length <= 2) {
    const assumeYes = args[1] === "--yes";
    if (args.length === 2 && !assumeYes) {
      throw new Error("--wrapper-update 只接受可选参数 --yes");
    }
    if (!assumeYes && (!process.stdin.isTTY || !process.stderr.isTTY)) {
      throw new Error("--wrapper-update 需要在交互式终端中运行");
    }
    await checkForUpdate({ force: true, assumeYes, failOnError: assumeYes });
    return;
  }

  await checkForUpdate();
  launchCodex(args);
})().catch((error) => {
  process.stderr.write(`[codex] ${error.message}\n`);
  process.exit(1);
});
