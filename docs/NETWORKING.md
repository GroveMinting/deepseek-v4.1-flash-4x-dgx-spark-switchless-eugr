# Switchless networking

The canonical fabric is a four-node, four-cable RoCE ring. It follows the
physical design demonstrated by
[`alexellis/glm-5.3-flash-4x-dgx-spark-switchless`](https://github.com/alexellis/glm-5.3-flash-4x-dgx-spark-switchless)
and uses the hardened `switchless-nccl` release pinned in `VERSIONS.lock`.

Management Ethernet or Wi-Fi remains connected for SSH, Gloo, bootstrap, and
API traffic. The two ConnectX-7 ports on each Spark carry NCCL traffic only.

## Physical ring

Use four passive 100 GbE QSFP28 DACs:

| Edge | First endpoint | Second endpoint | Subnet |
|---|---|---|---|
| 0–1 | node 0 port 1 | node 1 port 1 | `10.10.10.0/24` |
| 1–2 | node 1 port 0 | node 2 port 0 | `10.10.20.0/24` |
| 2–3 | node 2 port 1 | node 3 port 1 | `10.10.30.0/24` |
| 3–0 | node 3 port 0 | node 0 port 0 | `10.10.40.0/24` |

The default addresses are defined in `config/cluster.env.example`. Confirm
interface and HCA names independently on every node:

```bash
ip -br link
ls /sys/class/infiniband
```

Do not infer interface order from the example names.

## NCCL behavior

The immutable runtime contains:

- `switchless-nccl` v0.0.1;
- archive SHA-256
  `b4a686382a92e57b485ca1bf7cd0f9fde780a68f01ea902ac432b60505b2041f`;
- `libnccl.so.2` SHA-256
  `78cb83871792ec57d763d142e4cae26fc754ae284bcc81dcb2a7d50e17d4fa57`.

Canonical recipes set both `LD_PRELOAD` and `VLLM_NCCL_SO_PATH` to the verified
library. They also set `NCCL_SWITCHLESS_RING_ONLY=1`, force the ring algorithm,
select both ConnectX HCAs, and disable tree construction through the hardened
release's compatibility controls.

Each collective needs only the four physical neighbor edges. Static layer-3
routes between non-neighbor fabric subnets are not required for the NCCL ring.
Jumbo pings prove the individual links; only a four-rank GPU collective proves
the transport.

## Configuration and validation

The setup tool is dry-run-only unless both `--apply` and the confirmation token
are present.

```bash
./switchless/fabric-setup.sh --config config/cluster.env
```

Review its complete output and physically trace every cable. Then set:

```text
I_UNDERSTAND_SWITCHLESS_NETWORK_CHANGES="YES"
```

Apply and verify:

```bash
./switchless/fabric-setup.sh --config config/cluster.env --apply
./switchless/fabric-verify.sh --config config/cluster.env
./switchless/nccl-gate.sh --config config/cluster.env
```

Acceptance requires:

- all eight configured fabric addresses;
- correct netdev-to-HCA mappings;
- active RoCE v2 GIDs at the configured index;
- MTU 9000 on both rails of every node;
- jumbo-packet success on all four physical edges;
- identical runtime image IDs on all four nodes;
- a successful four-rank GPU all-reduce through the pinned NCCL library.

Fabric configuration is runtime-only. Reapply and repeat every gate after a
reboot or after Docker changes host firewall state. Setup refuses to run while
GPU compute processes are active.

## Rollback

Stop the cluster first:

```bash
./switchless/fabric-rollback.sh \
  --config config/cluster.env \
  --apply
```

Rollback removes only the configured project addresses and `DOCKER-USER`
rules, then returns both ConnectX interfaces to NetworkManager. It does not
change the management interface, images, model data, or eugr installation.

## Switched diagnostic fallback

A conventional switched RoCE path remains available strictly for fault
isolation. Connect one HCA from each Spark to the same correctly configured
100 GbE RoCE fabric, set `SWITCHED_HCA` and `SWITCHED_GID_INDEX`, and launch
with:

```bash
./run-deepseek-v41.sh \
  --config config/cluster.env \
  --runtime baseline \
  --fabric switched \
  --profile base \
  -d
```

The renderer gives these fallback recipes a `-switched` suffix and does not
preload the switchless NCCL library into them.

A switched success can help distinguish a model/runtime problem from a
direct-ring problem. It does not qualify the switchless configuration.

