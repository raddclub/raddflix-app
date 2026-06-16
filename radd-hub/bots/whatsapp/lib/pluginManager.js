'use strict';
const path = require('path');
const fs   = require('fs');
const { meetsRole } = require('./roles');
const fmt           = require('./format');
const db            = require('./db');
class PluginManager {
  constructor() {
    this.plugins = [];
    this.commandIndex = new Map();   
  }
  register(plugin, ctx) {
    if (!plugin || !plugin.name || !Array.isArray(plugin.commands)) {
      throw new Error('plugin must have { name, commands[] }');
    }
    this.plugins.push(plugin);
    for (const c of plugin.commands) {
      if (this.commandIndex.has(c.intent)) {
        const existing = this.commandIndex.get(c.intent);
        console.warn(`[plugin] intent "${c.intent}" overridden by ${plugin.name} (was ${existing.plugin.name})`);
      }
      this.commandIndex.set(c.intent, { plugin, command: c });
    }
    if (typeof plugin.init === 'function') {
      try { plugin.init(ctx); } catch (e) { console.error(`[plugin:${plugin.name}] init failed`, e); }
    }
    console.log(`[plugin] registered ${plugin.name} v${plugin.version || '1'} — intents: ${plugin.commands.map(c => c.intent).join(', ')}`);
  }
  registerDir(dir, ctx) {
    dir = path.resolve(dir);
    if (!fs.existsSync(dir)) return;
    for (const f of fs.readdirSync(dir).sort()) {
      if (!f.endsWith('.js')) continue;
      try {
        const mod = require(path.join(dir, f));
        this.register(mod, ctx);
      } catch (e) {
        console.error(`[plugin] failed to load ${f}:`, e.message);
      }
    }
  }
  list() { return this.plugins.map(p => ({ name: p.name, version: p.version || '1', intents: p.commands.map(c => c.intent) })); }
  async dispatch({ sock, jid, ctx, intent, role, helpers }) {
    const entry = this.commandIndex.get(intent.name);
    if (!entry) {
      return { handled: false };
    }
    const required = entry.command.role || 'free';
    if (!meetsRole(role, required)) {
      const brand = fmt.brand();
      const why = required === 'admin'
        ? '❌ Admins only.'
        : required === 'verified'
          ? `🔒 *${brand.name} Premium* members only.\n\nUpgrade with */price* to unlock this feature.`
          : '❌ Forbidden.';
      await sock.sendMessage(jid, { text: why + (required === 'verified' ? fmt.brandFooter() : '') }, { quoted: ctx });
      db.audit('intent.denied', helpers && helpers.senderJid, `${intent.name} need=${required} have=${role}`);
      return { handled: true, denied: true };
    }
    try {
      console.log(`[plugin:${entry.plugin.name}] calling handler for "${intent.name}"`);
      const out = await entry.command.handler({
        sock, jid, ctx, intent, role,
        brand: fmt.brand(),
        helpers,
        plugin: entry.plugin,
      });
      console.log(`[plugin:${entry.plugin.name}] handler for "${intent.name}" finished`);
      db.audit('intent.ok', helpers && helpers.senderJid, intent.name);
      return { handled: true, result: out };
    } catch (e) {
      console.error(`[plugin:${entry.plugin.name}] handler for "${intent.name}" threw:`, e.stack);
      db.audit('intent.error', helpers && helpers.senderJid, `${intent.name}: ${e.message}`);
      try {
        await sock.sendMessage(jid, { text: `⚠ Something went wrong handling that. Try */menu*.` }, { quoted: ctx });
      } catch {}
      return { handled: true, error: e.message };
    }
  }
}
module.exports = { PluginManager };