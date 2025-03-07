\section{Introduction}

\begin{code}[hide]
{-# OPTIONS --safe #-}
open import Ledger.Prelude as Prelude
  hiding (_<ᵇ_; _∧_; dec)
  renaming (_×_ to _∧_)
open import Data.Integer using (+_; 0ℤ; 1ℤ; -1ℤ)

module MidnightExample.Ledger
  (Hash : Type)
  ⦃ _ : DecEq Hash ⦄
  ⦃ _ : Hashable ℤ Hash ⦄
  ⦃ _ : Hashable₁ List Hash ⦄
  ⦃ _ : Hashable₂ _∧_ Hash ⦄
  where

import Data.Integer.Properties as ℤ
open import Relation.Nullary

instance
  _ = Conversion.fromBundle ℤ.+-0-commutativeMonoid

  Hashable-ℕ : Hashable ℕ Hash
  Hashable-ℕ .hash n = hash (+ n)

_<ᵇ_ : Maybe ℕ → Maybe ℕ → Bool
just a  <ᵇ just b  = a Prelude.<ᵇ b
just a  <ᵇ nothing = false
nothing <ᵇ just b  = true
nothing <ᵇ nothing = false
\end{code}

This is a small example of a ledger specification for Midnight. It
only assumes that we know how to hash some types and provides a step
function for the ledger together with a proof of a non-trivial
property.

\section{Epochs \& Consensus}

We define the number of slots in an epoch and a conversion function
from slots to epochs here, as well as a structure to refer to certain
points in the chain.

\begin{figure*}[h]
\AgdaTarget{Point, slot, blockHash, slotsInEpoch, epochOf}
\begin{code}
record Point : Type where
  field
    slot       : Maybe ℕ
    blockHash  : Hash

slotsInEpoch : ℕ
slotsInEpoch = 50

epochOf : Maybe ℕ → Maybe ℕ
epochOf nothing  = nothing
epochOf (just s) = just (s / slotsInEpoch)
\end{code}
\caption{Point- and epoch-related definitions}
\end{figure*}

\newpage

\section{Transactions \& Blocks}

Transactions can increment or decrement a counter that is stored in
the ledger, and blocks consist of a list of transactions and a header,
which contains some meta-information about the block. We also use the
accessor functions of the headers transitively, to access fields in
the header given the body.

\begin{figure*}[h]
\AgdaTarget{Tx, inc, dec, txDelta}
\begin{code}
data Tx : Type where
  inc  : Tx
  dec  : Tx

txDelta : Tx → ℤ
txDelta inc  = 1ℤ
txDelta dec  = -1ℤ

\end{code}
\begin{code}[hide]
txDelta-injective : Injective _≡_ _≡_ txDelta
txDelta-injective {inc} {inc} refl = refl
txDelta-injective {dec} {dec} refl = refl
instance
  Hashable-Tx : Hashable Tx Hash
  Hashable-Tx .hash = hash ∘ txDelta
\end{code}
\caption{Transactions}
\end{figure*}
\begin{figure*}[h]
\AgdaTarget{Header, slotNo, blockNo, blockHash, prev, nodeId, Block, header, body, blockPoint, computeBlockHash, addBlockHash}
\begin{code}
record Header : Type where
  field
    slotNo     : ℕ
    blockNo    : ℕ
    blockHash  : Hash
    prev       : ℕ
    nodeId     : ℕ

record Block : Type where
  field
    header  : Header
    body    : List Tx

  open Header header public

blockPoint : Block → Point
blockPoint b = record { slot = just slotNo ; blockHash = blockHash }
  where open Block b

computeBlockHash : Block → Hash
computeBlockHash b = hash (slotNo , blockNo , prev , body)
  where open Block b

addBlockHash : Block → Block
addBlockHash b = record b
  { header = record header { blockHash = computeBlockHash b } }
  where open Block b
\end{code}
\caption{Blocks and functions related to them}
\end{figure*}

\newpage

\section{Ledger}

The ledger state consists of a pointer to the previous block as well as a counter and two snapshots. Ticking a ledger state means to roll over the snapshots.
\begin{figure*}[h]
\AgdaTarget{LedgerState, tip, count, snapshot1, snapshot2, tickLedgerState}
\begin{AgdaSuppressSpace}
\begin{code}
record LedgerState : Type where
  field
    tip                  : Point
    count                : ℤ
    snapshot1 snapshot2  : ℤ

\end{code}
\begin{code}[hide]
open LedgerState
\end{code}
\begin{code}
tickLedgerState : ℕ → LedgerState → LedgerState
tickLedgerState newSlot st = if isNewEpoch
  then record st { snapshot1 = count st ; snapshot2 = snapshot1 st }
  else st
  where isNewEpoch = epochOf (Point.slot (tip st)) <ᵇ epochOf (just newSlot)
\end{code}
\end{AgdaSuppressSpace}
\caption{Ledger state and its tick function}
\end{figure*}

The ledger transition system updates the tip to point to the most
recent applied block, and increments/decrements the counter according
to the transactions. We also want to check some non-trivial
conditions, so we require the change to the counter to be non-zero and
that the hash in the header is correct.

\begin{figure*}[h]
\AgdaTarget{\_⊢\_⇀⦇\_,LEDGER⦈\_, LEDGER-inductive}
\begin{code}
data _⊢_⇀⦇_,LEDGER⦈_ : ⊤ → LedgerState → Block → LedgerState → Type where
  LEDGER-inductive : ∀ {Γ} {s} {b} →
    let open Block b
        acc = ∑ˡ[ x ← body ] txDelta x
        s'  = tickLedgerState slotNo s
    in ∙ acc ≢ 0ℤ        ∙ computeBlockHash b ≡ blockHash
    ────────────────────────────────
    Γ ⊢ s ⇀⦇ b ,LEDGER⦈
      record s' { tip = blockPoint b ; count = count s + acc }
\end{code}
\caption{The LEDGER transition system}
\end{figure*}

We can prove that this relation is a partial function and the proof gives us a step function.
As an example we also provide a function that does the same computation explicitly.

\begin{code}[hide]
pattern LEDGER-inductive⋯ x y = LEDGER-inductive (x , y)
unquoteDecl LEDGER-inductive-premises =
  genPremises LEDGER-inductive-premises (quote LEDGER-inductive)

instance
  Computational-LEDGER : Computational _⊢_⇀⦇_,LEDGER⦈_ ⊤
  Computational-LEDGER = record {Go}
    where module Go Γ s b (let H , ⁇ H? = LEDGER-inductive-premises {b}) where
      computeProof = case H? of λ where
        (yes p) → success (-, LEDGER-inductive p)
        (no _)  → failure tt

      completeness : _
      completeness s' (LEDGER-inductive p) rewrite dec-yes H? p .proj₂ = refl

open Computational ⦃...⦄
\end{code}
\begin{figure*}[h]
\begin{code}
LEDGER-step : ⊤ → LedgerState → Block → ComputationResult ⊤ LedgerState
LEDGER-step = compute

applyBlockTo : Block → LedgerState → Maybe LedgerState
applyBlockTo b st = let acc = ∑ˡ[ x ← Block.body b ] txDelta x in
  ifᵈ acc ≢ 0ℤ ∧ computeBlockHash b ≡ Block.blockHash b
    then just record st { tip = blockPoint b ; count = count st + acc }
    else nothing
\end{code}
\end{figure*}

\newpage

\section{Key properties}

This is Agda, so we can prove some properties. Since we check very few
things, and just repeating properties that we do check isn't
interesting, here's the only non-trivial property that I could think
of: That the counter in the ledger state does change.

We present three proofs here, one using the STS, one using the step
function generated from the STS, and one using the
\AgdaFunction{applyBlockTo} function to show why using the STS is more
convenient for proofs: Instead of tracing the function control flow to
extract properties, we can simply pattern-match for them. After we
obtained fact that the sum of changes induced by transactions is
non-zero, the proofs are identical.

\begin{code}[hide]
private variable
  s s' : LedgerState
  b : Block

open import Algebra.Properties.AbelianGroup ℤ.+-0-abelianGroup
\end{code}
\begin{figure*}[h]
\begin{code}
lemma : ∀ {x y} → y ≢ 0ℤ → x ≢ x + y
lemma y≢0 eq = y≢0 (identityʳ-unique _ _ (sym eq))

LEDGER-property₁ : _ ⊢ s ⇀⦇ b ,LEDGER⦈ s' → count s ≢ count s'
LEDGER-property₁ (LEDGER-inductive⋯ acc≢0 _) = lemma acc≢0

LEDGER-property₂ : LEDGER-step _ s b ≡ success s' → count s ≢ count s'
LEDGER-property₂ {s} {b} eq
  = LEDGER-property₁
  $ Equivalence.to (≡-success⇔STS {s = s} {sig = b}) eq

LEDGER-property₃ : applyBlockTo b s ≡ just s' → count s ≢ count s'
LEDGER-property₃ {b = b} h with
  (∑ˡ[ x ← Block.body b ] txDelta x) ≟ 0ℤ | computeBlockHash b ≟ Block.blockHash b | h
... | no acc≢0 | yes _ | refl = lemma acc≢0
... | no _     | no _  | ()
... | yes _    | _     | ()
\end{code}
\caption{Three proofs that the counter doesn't stay constant}
\end{figure*}
