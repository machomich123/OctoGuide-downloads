import crypto from 'node:crypto';

// A launcher-only verification cache. It never starts WoW or writes a token to
// disk. WoW still performs its own native SRP authentication after Play.
export class LoginPreflight {
  constructor({ authenticate, provision, now = () => Date.now(), validMs = 180000 }) {
    this.authenticate = authenticate;
    this.provision = provision;
    this.now = now;
    this.validMs = validMs;
    this.secret = crypto.randomBytes(32);
    this.generation = 0;
    this.pending = null;
    this.ready = null;
    this.current = '';
    this.state = 'idle';
  }

  fingerprint(account, password, url, native) {
    return crypto.createHmac('sha256', this.secret)
      .update(JSON.stringify([account, password, url, native]))
      .digest('hex');
  }

  status(account) {
    return {
      status: account === this.current ? this.state : 'idle',
      account: this.current,
      verified: !!(this.ready && this.ready.account === account &&
        this.ready.expires > this.now()),
    };
  }

  invalidate() {
    this.generation++;
    this.ready = null;
    this.pending = null;
    this.state = 'idle';
    this.current = '';
  }

  async prepare({ account, password, url, native = false }) {
    const digest = this.fingerprint(account, password, url, native);
    if (this.ready?.digest === digest && this.ready.expires > this.now()) {
      return { verified: true, cached: true };
    }
    if (this.pending?.digest === digest) {
      await this.pending.promise;
      return { verified: true, cached: false };
    }
    const generation = ++this.generation;
    this.ready = null;
    this.current = account;
    this.state = 'verifying';
    const task = (async () => {
      const token = await this.authenticate(url, account, password);
      if (native) await this.provision(account, password);
      if (generation !== this.generation) return;
      this.ready = {
        account, digest, token,
        expires: this.now() + this.validMs,
        native,
      };
      this.state = 'ready';
    })();
    this.pending = { digest, promise: task };
    try {
      await task;
      return { verified: generation === this.generation, cached: false };
    } catch (error) {
      if (generation === this.generation) {
        this.ready = null;
        this.state = 'unavailable';
      }
      throw error;
    } finally {
      if (generation === this.generation) this.pending = null;
    }
  }

  async take({ account, password, url, native = false }) {
    const digest = this.fingerprint(account, password, url, native);
    if (this.pending?.digest === digest) await this.pending.promise;
    if (this.ready?.digest !== digest || this.ready.expires <= this.now()) {
      await this.prepare({ account, password, url, native });
    }
    if (this.ready?.digest !== digest) throw new Error('Verification was superseded.');
    const ticket = this.ready;
    this.ready = null;
    this.state = 'idle';
    return ticket.token;
  }
}
