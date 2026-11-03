// Phones reaching the server (network.js): the address, the firewall, and the first phone.
import { expect, test } from "bun:test";
import { clientAddress, createReach, firewallState, lanAddress, NETWORK } from "../src/network.js";

const v4 = (address, internal = false) => ({ family: "IPv4", address, internal });
const LO = { lo0: [v4("127.0.0.1", true)] };
const WIFI = { ...LO, en0: [v4("172.24.240.193")] };
const OPEN = async () => ({ blocked: null, note: null });

function reachOn(nets, { firewall = OPEN, settings = {} } = {}) {
  const box = { nets, logs: [], errors: [] };
  const reach = createReach({
    settings: {
      lanAuto: true,
      port: 8080,
      publicUrl: "http://localhost:8080",
      phoneVitePort: null,
      ...settings,
    },
    log: (l) => box.logs.push(l),
    logError: (l) => box.errors.push(l),
    nets: () => box.nets,
    firewall,
    everyMs: 60_000,
  });
  box.reach = reach;
  return box;
}

test("lanAddress: Wi-Fi first, never a VPN or self-assigned address, null without a network", () => {
  expect(lanAddress({ utun4: [v4("10.8.0.2")], ...WIFI })).toEqual({
    ip: "172.24.240.193",
    iface: "en0",
  });
  expect(lanAddress({ ...LO, en0: [v4("169.254.12.7")], en5: [v4("192.168.1.3")] })).toEqual({
    ip: "192.168.1.3",
    iface: "en5",
  });
  expect(lanAddress({ ...LO, en0: [v4("169.254.12.7")] })).toBeNull();
  expect(lanAddress(LO)).toBeNull();
});

test("clientAddress: the peer, or the phone Vite forwarded for", () => {
  const srv = (address) => ({ requestIP: () => ({ address }) });
  const req = (headers = {}) => new Request("http://x/", { headers });
  expect(clientAddress(req(), srv("::ffff:172.24.240.50"))).toBe("172.24.240.50");
  expect(clientAddress(req({ "x-forwarded-for": "172.24.240.50" }), srv("::1"))).toBe(
    "172.24.240.50",
  );
  // Only a proxy on this Mac is believed.
  expect(clientAddress(req({ "x-forwarded-for": "1.2.3.4" }), srv("172.24.240.50"))).toBe(
    "172.24.240.50",
  );
});

test("no network: no phone address, and the banner says so instead of printing localhost", async () => {
  const { reach } = reachOn(LO);
  await reach.ready;
  expect(reach.url()).toBeNull();
  expect(reach.network()).toBe(NETWORK.noNetwork);
  expect(reach.banner()[0]).toContain("NO PHONE ADDRESS");
  reach.stop();
});

test("until a phone gets through, the address is unproven and the banner explains client isolation", async () => {
  const box = reachOn(WIFI, { settings: { publicUrl: "http://172.24.240.193:8080" } });
  const { reach } = box;
  await reach.ready;
  expect(reach.url()).toBe("http://172.24.240.193:8080");
  expect(reach.network()).toBe(NETWORK.noPhoneYet);
  expect(reach.banner().join(" ")).toContain("client isolation");
  // The Mac itself (loopback or its own address) proves nothing.
  reach.sawClient("127.0.0.1");
  reach.sawClient("172.24.240.193");
  expect(reach.network()).toBe(NETWORK.noPhoneYet);
  reach.sawClient("172.24.240.50");
  expect(reach.network()).toBe(NETWORK.phoneSeen);
  expect(reach.banner()).toEqual([]);
  expect(box.logs).toEqual([expect.stringContaining("a phone got through (172.24.240.50")]);
  reach.stop();
});

test("the address follows the Mac to another network, loudly, and the phone has to prove it again", async () => {
  const settings = { publicUrl: "http://172.24.240.193:8080" };
  const box = reachOn(WIFI, { settings });
  const { reach } = box;
  await reach.ready;
  reach.sawClient("172.24.240.50");
  box.nets = { ...LO, en0: [v4("172.20.10.4")] }; // the Mac joins a phone's hotspot
  reach.check();
  expect(reach.url()).toBe("http://172.20.10.4:8080");
  expect(reach.network()).toBe(NETWORK.noPhoneYet);
  expect(box.errors[0]).toContain(
    "THE PHONE ADDRESS CHANGED: phones now open http://172.20.10.4:8080 (en0), not http://172.24.240.193:8080",
  );
  box.nets = LO;
  reach.check();
  expect(reach.url()).toBeNull();
  expect(reach.network()).toBe(NETWORK.noNetwork);
  expect(box.errors.at(-1)).toContain("left the network (http://172.20.10.4:8080 is gone)");
  reach.stop();
});

test("PUBLIC_URL is kept as given, whatever the network does", async () => {
  const box = reachOn(LO, {
    settings: { lanAuto: false, publicUrl: "http://bebbikart.local:8080" },
  });
  await box.reach.ready;
  box.nets = WIFI;
  box.reach.check();
  expect(box.reach.url()).toBe("http://bebbikart.local:8080");
  expect(box.errors).toEqual([]);
  box.reach.stop();
});

test("a firewall that blocks the server is a problem; one that can't be read is an error", async () => {
  const blocked = reachOn(WIFI, {
    firewall: async () => ({
      blocked: "the macOS firewall blocks all incoming connections",
      note: null,
    }),
  });
  await blocked.reach.ready;
  expect(blocked.reach.network()).toBe(NETWORK.firewall);
  expect(blocked.reach.banner()[0]).toContain("PHONES ARE BLOCKED");
  expect(blocked.errors[0]).toContain("blocks all incoming connections");
  blocked.reach.stop();

  const unreadable = reachOn(WIFI, {
    firewall: async () => {
      throw new Error("socketfilterfw exited 1");
    },
  });
  await unreadable.reach.ready;
  expect(unreadable.errors[0]).toContain(
    "can't read the macOS firewall state: socketfilterfw exited 1",
  );
  unreadable.reach.stop();
});

test("firewallState reads socketfilterfw's answers", async () => {
  if (process.platform !== "darwin") return;
  const answers =
    (map) =>
    async (...args) =>
      map[args[0]];
  expect(
    await firewallState(
      process.execPath,
      answers({ "--getglobalstate": "Firewall is disabled. (State = 0)" }),
    ),
  ).toEqual({
    blocked: null,
    note: null,
  });
  const all = await firewallState(
    process.execPath,
    answers({
      "--getglobalstate": "Firewall is enabled. (State = 1)",
      "--getblockall": "Firewall has block all state set to enabled.",
    }),
  );
  expect(all.blocked).toContain("blocks all incoming connections");
  const app = await firewallState(
    process.execPath,
    answers({
      "--getglobalstate": "Firewall is enabled. (State = 1)",
      "--getblockall": "Firewall has block all state set to disabled.",
      "--getappblocked": "Incoming connection to /x/bun is blocked.",
    }),
  );
  expect(app.blocked).toContain("blocks incoming connections to");
  const asks = await firewallState(
    process.execPath,
    answers({
      "--getglobalstate": "Firewall is enabled. (State = 1)",
      "--getblockall": "Firewall has block all state set to disabled.",
      "--getappblocked": "Incoming connection to /x/bun is permitted.",
    }),
  );
  expect(asks).toEqual({ blocked: null, note: expect.stringContaining("click Allow") });
  await expect(
    firewallState(process.execPath, answers({ "--getglobalstate": "huh" })),
  ).rejects.toThrow("unexpected firewall state");
});
