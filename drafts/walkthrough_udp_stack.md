# Walkthrough — a MEDIUM design: Neosyn's UDP/IP stack

How a ~1,300-line, 15-task C⏚ design is organised, in what order it is built, and what each rung
of its test ladder checks. Read `cg_large_designs.md` first; this is that method applied to a
real core. (The core's source is a licensed Neosyn product and is not reproduced here — the
structure and the method are what carry over to your own design.)

**What it does.** Answers ARP requests and UDP datagrams addressed to the board: an Ethernet
frame comes in as bytes, the reply goes out as bytes. Below it sits an Ethernet MAC (a separate
project, pulled in with a `cg.deps` file); above it, nothing — the UDP payload is echoed.

---

## 1. The architecture, as boxes

```
ProtoTop                       (Ethernet frame in -> Ethernet frame out)
├── ExtractMacHeader           strip the 14-byte MAC header, keep the reply address + EtherType
├── frameForker (inline task)  route the frame body by EtherType: ARP or IP
├── ArpTop
│   ├── ARP_Recv               parse a request
│   ├── arp_handle (inline)    decide the reply fields
│   └── ARP_Send               emit the reply
├── IpTop
│   ├── IP_Recv                parse + check the IP header, pass the body on
│   ├── UDP_Top
│   │   ├── UDP_Recv           parse the UDP header
│   │   └── UDP_Send           build the reply datagram
│   ├── IP_Send                build the reply IP header (with ComputeChecksumIP)
│   └── MakeIPPacket           header + body -> one byte stream
├── FIFOs (std.fifo)           decouple the ARP and IP reply paths from the joiner
├── frameJoiner (inline task)  pick the reply that is ready, frame it
└── InsertMacHeader            prepend the MAC header for the reply
```

Four levels: atoms (the checksum), blocks (each `*_Recv`/`*_Send`), subsystems (`ArpTop`,
`UDP_Top`, `IpTop`), the top (`ProtoTop`). Shared types and constants — `typedef u48 mac`,
`typedef u32 ipv4`, the board's addresses — live in one `bundle Net_Constants`.

## 2. The links that matter

| link | type / protocol | why it is designed that way |
|---|---|---|
| every byte path (frame in, bodies, replies) | `framed u8` | each packet carries its own end: the consumer reads `.last` with the byte. A packet never ends because input paused. |
| parsed header fields (`srcIp`, `dstPort`, `protocol`, …) | bare levels, held | produced once per packet, read whenever the next stage needs them; they stay valid until the next packet's header. |
| `IpTop.busy` → `ExtractMacHeader` | bare `bool` | back-pressure: the IP side is still replying, do not start the next frame. |
| `IP_Send.frameLen` | `stream u16` | the length must be known before the joiner frames the reply; a stream makes the consumer wait for it. |
| ARP reply / IP reply → joiner | through 32–64-entry FIFOs | the two reply paths finish at different times; FIFOs let each run at its own pace. |

Write this table before the code. Every integration bug this design ever had was a row of it:
how a packet ends, who waits for whom, a value read one cycle too early.

## 3. Build order and the test at each rung

| rung | what is tested | test | how it checks |
|---|---|---|---|
| atom | `ComputeChecksumIP` | `TestChecksum` | a real IPv4 header from the textbook, checksum field zeroed → must give `0xB1E6`. One known answer from outside the design. |
| block | `ARP_Send` header | `Test_ArpSendHeader` | the 8 header bytes, one assert each (8 checks). |
| block | `ARP_Recv` with framed input | `Test_ArpRecvFramed` | parsed fields of a framed request. |
| block | `InsertMacHeader` | `Test_InsertMacHeader` | the 18 bytes it emits (18 checks). |
| block | `UDP_Send` | `TestUDPSend` | header fields and payload of the built datagram. |
| subsystem | IP → UDP receive path, PACED input | `Test_RxUdpPaced` | fields parsed correctly when bytes arrive with gaps. |
| top | `ProtoTop`, real frames | `TestProto` | a source task replays recorded ARP and UDP frames; a target task compares every reply byte with the expected reply. |
| top | the same, PACED | `TestProtoPaced` | the same frames with pauses inside them. |
| scenario | over the MAC both ways | `TestFullStack`, `TestFullStackPaced` | 1490 bytes through MAC transmit and receive and back. |

Each row was green — and asserted values — before the row below it was trusted.

## 4. Lessons from building it

- **A failing top test points at a symptom; a block test finds the cause.** When the top test
  failed at the first ARP payload bytes (`00 01` expected, `00 00` received), the fix came from
  a new test that drove `ARP_Send` alone and checked its 8 header bytes — not from staring at
  the top. Add the block test, then fix.
- **Anchor each block test to a known answer from outside the design** (a textbook checksum, a
  captured packet). A test whose expected values were computed by the same code it checks
  proves nothing.
- **Every protocol-level test has a paced twin.** Back-to-back input hides any bug in how a
  block holds its state across a pause. Write both from the start.
- **Count the checks.** The gate records how many asserts each test must evaluate (1, 8, 18 …)
  and fails if fewer run. A test that silently stopped checking still prints "passed".
- **"It elaborates" proves nothing about behaviour.** The protocol tests run as value
  simulations on the bytecode simulator AND on the generated Verilog and VHDL: the hardware
  can disagree with the simulator, and only the hardware ships.
- **Compose projects, do not copy them.** The MAC lives in its own project with its own tests;
  `cg.deps` (one line: `../Ethernet`) makes its tasks resolvable here.

## 5. The same plan for your design

A medium design of your own — a packet parser, a protocol bridge, a video pipeline — fits the
same shape: 8–15 tasks in 3–4 levels, one shared bundle, `framed` byte paths with held header
fields beside them, FIFOs where two paths re-join, and a ladder of 8–12 tests from one atom with
a known answer up to a full-scenario test with a paced twin. Start with the Links table.
