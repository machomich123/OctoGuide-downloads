import crypto from 'node:crypto';

// Launcher-only authentication, with optional live WoW session preparation.
// Neither secrets nor session keys are serialized and no WoW process starts.
export class LoginPreflight {
  constructor({ authenticate, provision, prepareSession = null, now = () => Date.now(), validMs = 180000 }) {
    this.authenticate = authenticate;
    this.provision = provision;
    this.prepareSession = prepareSession;
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
        this.usable(this.ready)),
      gameSessionPrepared: !!(this.ready?.prepared?.usable()),
      charactersPrefetched: !!this.ready?.prepared?.world?.characterList,
    };
  }

  invalidate() {
    this.generation++;
    void this.ready?.prepared?.stop();
    this.ready = null;
    this.pending = null;
    this.state = 'idle';
    this.current = '';
  }

  usable(ticket) {
    return !!(ticket && ticket.expires > this.now() &&
      (!ticket.prepared || ticket.prepared.usable()));
  }

  savedPassword(account, url) {
    return this.ready?.fromSaved && this.ready.account === account &&
      this.ready.url === url && this.usable(this.ready) ? this.ready.prepared?.password || '' : '';
  }

  async prepare({ account, password, url, native = false, fromSaved = false }) {
    const digest = this.fingerprint(account, password, url, native);
    if (this.ready?.digest === digest && this.usable(this.ready)) {
      return { verified: true, cached: true };
    }
    if (this.pending?.digest === digest) {
      await this.pending.promise;
      return { verified: this.ready?.digest === digest && this.usable(this.ready), cached: false };
    }
    const generation = ++this.generation;
    const old = this.ready;
    this.ready = null;
    this.current = account;
    this.state = 'verifying';
    const task = (async () => {
      if (old?.prepared) await old.prepared.stop();
      const token = await this.authenticate(url, account, password);
      if (native) await this.provision(account, password);
      if (generation !== this.generation) return;
      const prepared = native && this.prepareSession ?
        await this.prepareSession({ account, password, url, token }) : null;
      if (generation !== this.generation) { await prepared?.stop(); return; }
      this.ready = {
        account, digest, token, prepared, fromSaved, url,
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

  async takeTicket({ account, password, url, native = false }) {
    const digest = this.fingerprint(account, password, url, native);
    if (this.pending?.digest === digest) await this.pending.promise;
    if (this.ready?.digest !== digest || !this.usable(this.ready)) {
      await this.prepare({ account, password, url, native });
    }
    if (this.ready?.digest !== digest) throw new Error('Verification was superseded.');
    const ticket = this.ready;
    this.ready = null;
    this.state = 'idle';
    return ticket;
  }

  async take(payload) { return (await this.takeTicket(payload)).token; }
}
