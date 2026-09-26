import { ConnectKitButton } from 'connectkit'
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useSwitchChain,
  useWatchContractEvent,
} from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { motion, AnimatePresence } from 'framer-motion'
import { Loader2, CheckCircle2, AlertCircle, Flame, CalendarCheck, ExternalLink, Users } from 'lucide-react'
import { useState, useCallback } from 'react'
import { toast } from 'sonner'
import { buildTxExplorerUrl, buildAddressExplorerUrl } from '@/onchain-facts'

// ── Contract Config ────────────────────────────────────────────────────────────
const CONTRACT_ADDRESS = '0x6863584402f61ec2b00ce0d4ea36a2af8effa826' as const
const TARGET_CHAIN_ID = arcTestnet.id

const ABI = [
  {
    type: 'function',
    name: 'checkIn',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'getUserStats',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [
      { name: 'userTotalCheckIns', type: 'uint256' },
      { name: 'userStreak', type: 'uint256' },
      { name: 'userLastCheckIn', type: 'uint256' },
      { name: 'canCheckInNow', type: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getRecentCheckIns',
    inputs: [],
    outputs: [
      {
        name: 'entries',
        type: 'tuple[]',
        components: [
          { name: 'user', type: 'address' },
          { name: 'timestamp', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'event',
    name: 'CheckedIn',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'timestamp', type: 'uint256', indexed: false },
      { name: 'totalCheckIns', type: 'uint256', indexed: false },
      { name: 'streak', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'error',
    name: 'AlreadyCheckedInToday',
    inputs: [],
  },
] as const

// ── Helpers ────────────────────────────────────────────────────────────────────
const formatAddress = (addr: string) => `${addr.slice(0, 6)}…${addr.slice(-4)}`

const formatTimestamp = (ts: bigint) => {
  const d = new Date(Number(ts) * 1000)
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

const parseCheckInError = (error: unknown): string => {
  const msg = (error as Error)?.message?.toLowerCase() ?? ''
  if (msg.includes('user rejected') || msg.includes('denied')) return 'Transaction cancelled.'
  if (msg.includes('alreadycheckedintoday') || msg.includes('already')) return 'Already checked in today. Come back in 24 hours.'
  if (msg.includes('insufficient funds') || msg.includes('exceeds balance')) return 'Insufficient balance for gas. Get test USDC from the sidebar.'
  if (msg.includes('network') || msg.includes('timeout')) return 'Network error. Check your connection and try again.'
  if (msg.includes('reverted')) return 'Transaction failed. Already checked in today.'
  return 'Something went wrong. Please try again.'
}

// ── Glass tokens ───────────────────────────────────────────────────────────────
const glassCard: React.CSSProperties = {
  background: 'rgba(255,255,255,0.64)',
  backdropFilter: 'blur(24px) saturate(180%)',
  WebkitBackdropFilter: 'blur(24px) saturate(180%)',
  border: '1px solid rgba(255,255,255,0.68)',
  boxShadow: '0 8px 32px rgba(18,45,69,0.08), inset 0 1px 0 rgba(255,255,255,0.55)',
}

const glassInner: React.CSSProperties = {
  background: 'rgba(255,255,255,0.46)',
  border: '1px solid rgba(255,255,255,0.56)',
}

// ── App ────────────────────────────────────────────────────────────────────────
export default function App() {
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const wrongChain = isConnected && chainId !== TARGET_CHAIN_ID

  const [txError, setTxError] = useState<string | null>(null)

  // Write
  const {
    writeContract,
    data: txHash,
    isPending,
    reset: resetWrite,
  } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  // Read user stats
  const {
    data: userStats,
    refetch: refetchStats,
  } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: 'getUserStats',
    args: address ? [address] : undefined,
    chainId: TARGET_CHAIN_ID,
    query: { enabled: !!address },
  })

  // Read recent check-ins
  const {
    data: recentCheckIns,
    refetch: refetchRecent,
  } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: 'getRecentCheckIns',
    chainId: TARGET_CHAIN_ID,
  })

  const [totalCheckIns, streak, lastCheckIn, canCheckInNow] = userStats ?? [0n, 0n, 0n, true]

  // Watch for events to auto-refresh
  useWatchContractEvent({
    address: CONTRACT_ADDRESS,
    abi: ABI,
    eventName: 'CheckedIn',
    chainId: TARGET_CHAIN_ID,
    onLogs() {
      void refetchStats()
      void refetchRecent()
    },
  })

  const handleCheckIn = useCallback(() => {
    if (wrongChain) {
      switchChain({ chainId: TARGET_CHAIN_ID })
      return
    }
    setTxError(null)
    resetWrite()
    writeContract(
      {
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'checkIn',
      },
      {
        onSuccess: () => {
          toast.success('Check-in submitted!')
        },
        onError: (err) => {
          const msg = parseCheckInError(err)
          setTxError(msg)
          toast.error(msg)
        },
      },
    )
  }, [wrongChain, switchChain, writeContract, resetWrite])

  const txUrl = txHash ? buildTxExplorerUrl(TARGET_CHAIN_ID, txHash) : undefined

  const ctaLabel = (() => {
    if (!isConnected) return 'Connect Wallet'
    if (wrongChain) return 'Switch to Arc Testnet'
    if (isPending) return null // spinner
    if (isConfirming) return null // spinner
    if (isSuccess) return 'Checked In!'
    if (canCheckInNow === false) return 'Already Checked In Today'
    return 'Check In Today'
  })()

  const ctaDisabled =
    !isConnected ||
    isPending ||
    isConfirming ||
    isSuccess ||
    canCheckInNow === false

  return (
    <div
      className="relative min-h-dvh overflow-hidden"
      style={{ background: 'var(--bg-gradient)' }}
    >
      {/* Ambient blobs */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div
          style={{
            position: 'absolute',
            top: '8%',
            left: '5%',
            width: 280,
            height: 280,
            borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(133,177,237,0.22) 0%, transparent 70%)',
            filter: 'blur(60px)',
          }}
        />
        <div
          style={{
            position: 'absolute',
            bottom: '8%',
            right: '8%',
            width: 260,
            height: 260,
            borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(255,205,131,0.20) 0%, transparent 70%)',
            filter: 'blur(58px)',
          }}
        />
      </div>

      <div className="relative z-10 mx-auto max-w-md px-4 pb-10 pt-6">
        {/* Header */}
        <header className="mb-6 flex items-center justify-between">
          <div>
            <span className="display text-xl font-bold" style={{ color: 'var(--ink)' }}>
              Daily Check-In
            </span>
            <p className="text-xs mt-0.5" style={{ color: 'var(--muted)' }}>
              Arc Testnet
            </p>
          </div>
          <ConnectKitButton />
        </header>

        <main className="space-y-3">
          {/* Hero stats card */}
          <motion.section
            className="rounded-3xl p-5"
            style={glassCard}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3 }}
          >
            <div className="flex items-center gap-1.5 mb-4">
              <div
                className="flex size-5 items-center justify-center rounded-md"
                style={{ background: 'rgba(18,45,69,0.08)' }}
              >
                <CalendarCheck className="size-3" style={{ color: 'var(--accent)' }} />
              </div>
              <span className="text-xs font-semibold tracking-wide uppercase" style={{ color: 'var(--muted)' }}>
                Your Stats
              </span>
            </div>

            {isConnected ? (
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-2xl p-4" style={glassInner}>
                  <p className="text-xs font-medium mb-1" style={{ color: 'var(--subtle)' }}>
                    Total Check-Ins
                  </p>
                  <p className="display text-3xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
                    {Number(totalCheckIns)}
                  </p>
                </div>

                <div className="rounded-2xl p-4" style={glassInner}>
                  <p className="text-xs font-medium mb-1 flex items-center gap-1" style={{ color: 'var(--subtle)' }}>
                    <Flame className="size-3" />
                    Current Streak
                  </p>
                  <p className="display text-3xl font-bold tabular-nums" style={{ color: Number(streak) > 0 ? 'var(--success)' : 'var(--subtle)' }}>
                    {Number(streak)}
                    <span className="text-base font-medium ml-1" style={{ color: 'var(--subtle)' }}>
                      day{Number(streak) !== 1 ? 's' : ''}
                    </span>
                  </p>
                </div>
              </div>
            ) : (
              <div className="rounded-2xl p-4 text-center" style={glassInner}>
                <p className="text-sm" style={{ color: 'var(--muted)' }}>
                  Connect your wallet to view your stats
                </p>
              </div>
            )}

            {/* Last check-in time */}
            {isConnected && lastCheckIn !== undefined && Number(lastCheckIn) > 0 && (
              <p className="mt-3 text-xs" style={{ color: 'var(--subtle)' }}>
                Last check-in: {formatTimestamp(lastCheckIn)}
              </p>
            )}
          </motion.section>

          {/* CTA */}
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: 0.05 }}
          >
            <button
              disabled={ctaDisabled}
              onClick={handleCheckIn}
              className="w-full rounded-2xl py-4 text-sm font-semibold text-white transition-all hover:scale-[1.01] active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-50"
              style={{ background: isSuccess ? 'var(--success)' : 'var(--accent)' }}
            >
              {isPending ? (
                <span className="flex items-center justify-center gap-2">
                  <Loader2 className="size-4 animate-spin" />
                  Confirm in wallet...
                </span>
              ) : isConfirming ? (
                <span className="flex items-center justify-center gap-2">
                  <Loader2 className="size-4 animate-spin" />
                  Confirming on chain...
                </span>
              ) : isSuccess ? (
                <span className="flex items-center justify-center gap-2">
                  <CheckCircle2 className="size-4" />
                  Checked In!
                </span>
              ) : (
                ctaLabel
              )}
            </button>
          </motion.div>

          {/* Transaction status */}
          <AnimatePresence>
            {(isSuccess || txError) && (
              <motion.div
                key={isSuccess ? 'success' : 'error'}
                className="rounded-2xl p-4"
                style={glassInner}
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ duration: 0.25 }}
              >
                {isSuccess && (
                  <div className="space-y-1">
                    <p className="text-sm font-semibold flex items-center gap-1.5" style={{ color: 'var(--success)' }}>
                      <CheckCircle2 className="size-4" />
                      Check-in confirmed onchain
                    </p>
                    {txUrl && (
                      <a
                        href={txUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="inline-flex items-center gap-1 text-xs"
                        style={{ color: 'var(--accent-hover)' }}
                      >
                        View transaction <ExternalLink className="size-3" />
                      </a>
                    )}
                  </div>
                )}
                {txError && !isSuccess && (
                  <p className="text-sm flex items-center gap-1.5" style={{ color: 'var(--danger)' }}>
                    <AlertCircle className="size-4 flex-shrink-0" />
                    {txError}
                  </p>
                )}
              </motion.div>
            )}
          </AnimatePresence>

          {/* Recent check-ins feed */}
          <motion.section
            className="rounded-3xl p-5"
            style={glassCard}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: 0.1 }}
          >
            <div className="flex items-center gap-1.5 mb-4">
              <div
                className="flex size-5 items-center justify-center rounded-md"
                style={{ background: 'rgba(18,45,69,0.08)' }}
              >
                <Users className="size-3" style={{ color: 'var(--accent)' }} />
              </div>
              <span className="text-xs font-semibold tracking-wide uppercase" style={{ color: 'var(--muted)' }}>
                Recent Check-Ins
              </span>
            </div>

            {!recentCheckIns || recentCheckIns.length === 0 ? (
              <div className="rounded-2xl p-4 text-center" style={glassInner}>
                <p className="text-sm" style={{ color: 'var(--muted)' }}>
                  No check-ins yet. Be the first!
                </p>
              </div>
            ) : (
              <div className="space-y-2">
                {(recentCheckIns as readonly { user: string; timestamp: bigint }[])
                  .slice(0, 20)
                  .map((entry, i) => (
                    <motion.div
                      key={`${entry.user}-${entry.timestamp.toString()}`}
                      className="flex items-center justify-between rounded-xl px-3 py-2.5"
                      style={glassInner}
                      initial={{ opacity: 0, x: -4 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ duration: 0.2, delay: i * 0.02 }}
                    >
                      <div className="flex items-center gap-2">
                        <div
                          className="size-7 rounded-full flex items-center justify-center text-xs font-semibold flex-shrink-0"
                          style={{ background: 'rgba(18,45,69,0.08)', color: 'var(--ink)' }}
                        >
                          {entry.user.slice(2, 4).toUpperCase()}
                        </div>
                        <div>
                          <a
                            href={buildAddressExplorerUrl(TARGET_CHAIN_ID, entry.user)}
                            target="_blank"
                            rel="noreferrer"
                            className="mono text-xs font-medium hover:underline"
                            style={{ color: 'var(--ink-2)' }}
                          >
                            {formatAddress(entry.user)}
                          </a>
                          <p className="text-xs mt-0.5" style={{ color: 'var(--subtle)' }}>
                            {formatTimestamp(entry.timestamp)}
                          </p>
                        </div>
                      </div>
                      {address?.toLowerCase() === entry.user.toLowerCase() && (
                        <span
                          className="text-xs font-semibold px-2 py-0.5 rounded-full"
                          style={{ background: 'rgba(26,128,71,0.1)', color: 'var(--success)' }}
                        >
                          You
                        </span>
                      )}
                    </motion.div>
                  ))}
              </div>
            )}
          </motion.section>

          {/* Contract info */}
          <motion.div
            className="rounded-2xl px-4 py-3 flex items-center justify-between"
            style={glassInner}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.3, delay: 0.15 }}
          >
            <span className="mono text-xs" style={{ color: 'var(--subtle)' }}>
              {formatAddress(CONTRACT_ADDRESS)}
            </span>
            <a
              href={`https://explorer.testnet.arc.io/address/${CONTRACT_ADDRESS}`}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1 text-xs font-medium"
              style={{ color: 'var(--accent-hover)' }}
            >
              ArcScan <ExternalLink className="size-3" />
            </a>
          </motion.div>
        </main>
      </div>
    </div>
  )
}
