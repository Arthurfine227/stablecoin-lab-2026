# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:

The current design gives the Vault `MINTER_ROLE`, while the same role authorizes both `mint` and `burn(address, amount)`. As a result, the Vault can destroy tokens held by any user without that user's approval. This creates a confiscation risk and makes a compromised Vault especially dangerous. An attacker controlling the Vault could erase user balances, disrupt redemption, or manipulate the relationship between recorded token supply and collateral. Even if the feature is intended for redemption, its authority is broader than necessary.

I would remove the arbitrary-address burn function from `SimpleStablecoin`. Instead, burning should operate only on tokens owned by the caller, for example through a `burn(uint256 amount)` function similar to `ERC20Burnable`. During redemption, `Vault.redeem(amount)` should first transfer `amount` of stablecoins from the user to the Vault using `transferFrom`, which requires the user's prior approval. The Vault would then burn only the tokens held at its own address and release the corresponding collateral to the user. Alternatively, a `burnFrom` design could be used, but it must consume an explicit allowance from the token holder. The Vault may retain permission to mint against verified deposits, but it should not have unrestricted power to burn balances belonging to arbitrary accounts.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:

In production, these three roles should be separated according to the principle of least privilege. `DEFAULT_ADMIN_ROLE` should be held by a high-security multisignature wallet, ideally combined with a timelock. It should be used only for rare governance actions such as granting, revoking, or rotating roles. Its signers should be independent and its keys should be stored securely, because compromise of the administrator would allow an attacker to change every other permission.

`MINTER_ROLE` should be granted only to the audited Vault or a dedicated issuance controller that mints tokens after verified collateral has been received. It should not be held by an ordinary employee wallet. Production safeguards could include per-transaction and daily minting limits, monitoring, and an emergency revocation mechanism.

`PAUSER_ROLE` should be held by a separate emergency security council or operational multisignature wallet. It needs to react faster than the administrator, but it should only be able to pause and unpause specified operations, not grant roles or mint tokens. Pause actions should generate alerts, require documented reasons, and be reviewed after a limited period. Using separate holders reduces the chance that one compromised key can mint tokens, disable the system, and take control of governance at the same time.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:

The current pause check is placed in `_update`, which is used for ordinary transfers, minting, and burning. Therefore, a global pause also prevents the burn performed during `Vault.redeem`, trapping users when they may most urgently want to exit. To pause transfers while allowing redemption, I would distinguish the three types of balance update by examining the `from` and `to` addresses. An ordinary transfer has both `from != address(0)` and `to != address(0)`, minting has `from == address(0)`, and burning has `to == address(0)`.

The overridden `_update` function should enforce the transfer pause only when both addresses are non-zero. A burn associated with redemption would therefore remain possible while peer-to-peer transfers are frozen. However, allowing all minting during an emergency may be undesirable, so issuance should have a separate control in the Vault. For example, `deposit` could be disabled by an `issuancePaused` flag while `redeem` remains enabled. This produces two independent emergency controls: one for transfers and new issuance, and another—used only in extreme circumstances—for redemption. Tests should confirm that paused transfers revert, deposits follow the selected emergency policy, and a fully collateralized holder can still burn stablecoins and recover collateral. This design preserves an orderly exit channel instead of locking every user into the system.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:

Closing the redemption channel removes the mechanism that connects a token or fund share to its underlying assets. In the 2008 money-market fund case, freezing redemptions prevented investors from receiving cash at the stated net asset value. Although the freeze may have slowed immediate asset sales, it also trapped investors, increased uncertainty, and removed confidence that the claim could be converted into money. Investors then had stronger reasons to sell in any available secondary market, potentially at a large discount.

Keeping redemption open creates a different dynamic. During the 2023 USDC depeg, uncertainty about reserves held at the failed bank pushed the market price below one dollar. However, the continued expectation that eligible holders could redeem USDC at par preserved an arbitrage path: a participant could buy discounted USDC and later redeem it for one dollar. That expectation helped place a floor under the price and supported recovery after the reserve situation became clearer.

Open redemption is not costless. It can accelerate outflows and force an issuer to maintain sufficient liquid reserves and reliable banking access. Nevertheless, for a fully backed stablecoin, redemption is the principal mechanism supporting the peg. Closing it may protect liquidity temporarily, but it weakens the central promise of convertibility and can turn a temporary confidence shock into a deeper depeg.

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:

This coin can depeg through at least two broad classes of failure. The first is an issuance or permission failure. If an attacker, compromised Vault, or malicious administrator obtains `MINTER_ROLE`, they can mint stablecoins without depositing matching collateral. In that case, `totalSupply()` increases while `totalCollateral()` remains unchanged. The invariant `totalCollateral() >= totalSupply()` becomes false immediately. This is the failure demonstrated in Ex3, where unauthorized economic issuance was possible after the attacker received the role.

The second class is collateral loss or impairment. Collateral might be transferred out of the Vault, stolen through a contract vulnerability, frozen by another issuer, or lose economic value. If on-chain USDC leaves the Vault, `totalCollateral()` decreases while supply remains outstanding, so the invariant also fails. However, the present invariant measures token units rather than their real market value. If USDC itself depegs, the Vault may still report one collateral unit for every SUSD unit even though the collateral is worth less than one dollar.

A third possibility is a liquidity or confidence depeg while the accounting invariant still holds. Redemptions may be paused, the blockchain may be congested, or users may doubt the administrator or reserves. Therefore, the invariant is necessary for solvency but not sufficient to guarantee a one-dollar market price, reliable redemption, or confidence in the system.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:

After obtaining `MINTER_ROLE`, the attacker mints 1,000,000 SUSD without depositing any USDC. The attacker has therefore created an unbacked claim on the Vault. If the Vault contains collateral deposited by legitimate users, the attacker can call `redeem` with the newly created SUSD. The Vault burns the attacker's tokens and transfers an equivalent amount of USDC to the attacker. The attacker contributes no collateral but extracts collateral belonging economically to honest holders. Afterward, the remaining legitimate SUSD is undercollateralized, even though the attacker's counterfeit tokens have been burned.

The best place to stop the attack is before unbacked minting occurs. `MINTER_ROLE` should belong only to a narrowly designed Vault that mints within the same transaction in which verified collateral is received. The role should not be granted to externally controlled accounts. Administrative role changes should require a multisignature approval, timelock, monitoring, and possibly minting limits. The system could also check the collateral invariant before and after issuance.

A check during redemption could detect that the system is already undercollateralized and prevent further losses, but it would also trap legitimate users and would not repair the original damage. Tracking each depositor's collateral separately could limit theft in some designs, but it would reduce fungibility. Therefore, strict control of the minting path and immediate detection of unauthorized role changes are the most important protections.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:

The same invariant could be expressed conceptually for US Treasuries, but it could not be measured as simply or as reliably as an on-chain MockUSDC balance. The smart contract cannot directly observe Treasury securities held by a bank, broker, custodian, or special-purpose vehicle. It would need an off-chain report or oracle stating the quantity, ownership, market value, and availability of those assets. The system would therefore introduce oracle risk, reporting delays, valuation errors, and the possibility of false or duplicated reserve claims.

Treasuries also change value as interest rates move. A portfolio may have sufficient face value but insufficient current liquidation value. The collateral calculation would need market prices, accrued interest, maturity information, and conservative haircuts. There is also a liquidity mismatch: stablecoins can trade and be redeemed continuously, while Treasury markets, banks, and custodians operate during limited hours and settlement may take time. Rapid redemptions could require selling assets at a discount.

Legal and operational issues also appear. The securities may be subject to liens, custodial failure, sanctions, or competing claims in bankruptcy. A better invariant would use verified market value after haircuts rather than face value and would combine oracle data with independent audits, custodian attestations, asset segregation, and liquidity reserves. It would remain a trust-dependent representation of collateral, not a purely on-chain guarantee.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:

A physical building cannot be transferred directly into a smart contract. A legal entity, such as a bankruptcy-remote special-purpose vehicle or trust, would first acquire and hold legal title to the property. The on-chain token or Vault position would represent a contractual beneficial interest in that entity or a secured claim against it. The legal documents must clearly connect token-holder rights to the building, rental income, sale proceeds, and enforcement procedures. Otherwise, the blockchain record would not guarantee ownership of the real asset.

Several off-chain roles would be required. A trustee or regulated custodian would protect the asset for token holders. A property manager would collect rent and maintain the building. Independent valuers would provide periodic valuations, while auditors would verify ownership, liabilities, and cash flows. An oracle or authorized reporting agent would transmit approved valuations and occupancy information on-chain. Insurers, lawyers, banks, and redemption or transfer agents would also be necessary.

The structure would need to address mortgages, taxes, maintenance costs, tenant vacancies, insurance claims, and bankruptcy. KYC, AML, securities regulation, and restrictions on property ownership may also apply. Because a building is illiquid and cannot be sold instantly, immediate stablecoin redemption would be risky. The system would need substantial cash reserves, conservative valuation haircuts, overcollateralization, redemption limits, or committed credit facilities to manage the mismatch between liquid tokens and an illiquid building.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:
The scenario I consider most likely to be attacked is compromise or misuse of the administrative role. The administrator can grant and revoke `MINTER_ROLE` or `PAUSER_ROLE`, so control of one privileged key can change the security assumptions of the entire system without modifying the contract code. An attacker who obtains that key could authorize an external account to mint unbacked SUSD, as demonstrated in Ex3, revoke permissions from legitimate system components, or disrupt transfers and redemption by abusing the pause mechanism.

Privileged keys are attractive targets because phishing, leaked credentials, malicious insiders, insecure signing devices, and operational mistakes may be easier to exploit than audited Solidity code. The impact would also be unusually large because the administrator controls several downstream permissions. I would mitigate this risk by separating the role holders, placing administrative authority behind an independent multisignature wallet, and applying a timelock to non-emergency role changes. The system should also monitor role events and unusual minting activity in real time, impose transaction and daily minting limits, maintain a documented emergency response process, and provide a rapid method for revoking compromised operational roles.