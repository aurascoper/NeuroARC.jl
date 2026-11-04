# Physical Model Specification: Sub-Micron Radiation Transport, Nucleic-Acid Strand Scission, and Track Reconstruction

> [!IMPORTANT]
> **Epistemic & Scope Boundaries**
> - **Document Status**: Standalone Biophysical & Radiation-Transport Model Specification (Proposal & Simulation Track).
> - **Primary Literature Baseline**:
>   1. Drukier, A., Freese, K., Lopez, A., Spergel, D., Cantor, C., Church, G., & Sano, T. (2015). *New Dark Matter Detectors using DNA or RNA for Nanometer Tracking*. `arXiv:1206.6809v2` ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf)).
>   2. O'Hare, C. A. J., Matsos, V. G., Newton, J., Smith, K., Hochstetter, J., Jaiswar, R., Kyaw, W., McNamara, A., Kuncic, Z., Nagaraja Grellscheid, S., & Boehm, C. (2022). *Particle detection and tracking with DNA*. *The European Physical Journal C*, 82(4), 306 (`arXiv:2105.11949`, DOI: `10.1140/epjc/s10052-022-10264-6`).
> - **Non-Claims**:
>   1. **Not Experimental Validation**: Both Drukier et al. (2015) and O'Hare et al. (2022) present theoretical detector proposals and Monte Carlo (`SRIM`, `ASTAR`, `Geant4-DNA`) simulations with unresolved laboratory calibration challenges.
>   2. **Not Evidence for Prebiotic Synthesis or Radiotrophy**: This model parameterizes radiation-induced nucleic-acid **damage** (phosphodiester backbone cleavage as a passive dosimetric/tracking record). It does not model or evidence radiation-powered RNA polymerization, biofilm matrix formation, or metabolic radiotrophy.
>   3. **Strict Decoupling from `NeuroARC.jl` and Release Engineering**: All physical constants and functions placed in [backends.jl](file:///Users/aurascoper/.gemini/antigravity/scratch/NeuroARC.jl/src/backends.jl#L1752-L1949) belong in this standalone biophysical specification and must remain off the October 29 to November 1, 2026 web/mobile release critical path ([release_blocker_audit_oct29_nov1.md](file:///Users/aurascoper/.gemini/antigravity/brain/117f7eb5-27b2-4957-9f56-0fc102f31523/release_blocker_audit_oct29_nov1.md)).

---

## 1. System Geometry and Explicit Separation of Readout Architectures

A critical modeling requirement is separating the two distinct detector geometries proposed in Drukier et al. (2015), which have different spatial resolutions and readout physics:

| Parameter / Feature | Architecture A: Hanging ssNA Curtain + PCR/Sequencing ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), pp. 8-11) | Architecture B: Stretched 23S-rRNA Coverslip + TIRF ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), p. 12) |
| :--- | :--- | :--- |
| **Module Layer Stack** | $1\ \mu\text{m}$ Mylar backing + $5\text{ to }10\text{ nm}$ metal foil ($\text{Au}$, $\text{W}$, $\text{Sn}$, $\text{Cu}$) + hanging ssNA curtain in $\text{He}$ or $\text{N}_2$ gas + bottom capture plate | $25 \times 25 \times 0.1\text{ mm}$ coverslip surface with stretched bacterial 23S-rRNA ($2,904\text{ nt}$, $1,400\text{ nm}$ length) |
| **Strand Anchoring & Tension** | Top $5'$ thiol-Au or biotin-streptavidin bond; bottom $3\text{ to }4\text{ nm} \times 50\text{ nm}$ magnetizable nanorod weight | Hybridized at both $5'$ and $3'$ ends via complementary $10\text{-mer}$ oligonucleotides immobilized on coverslip |
| **Lateral ($x$-$y$) Resolution** | **$1\ \mu\text{m} \times 1\ \mu\text{m}$** (defined by the 20 to 100 base bundle terminus barcode; individual strands have $10\text{ nm}$ polka-dot pitch within a bundle) | Diffraction-limited TIRF optical pixel resolution in $x$-$y$ across $10^7$ coverslips scanned at $120\text{ coverslips/s}$ |
| **Axial ($z$) Resolution** | **$\sim 0.7\text{ nm}$** single-base sequencing resolution along fully stretched ssNA ($100\text{ to }200\text{ nm}$ off-the-shelf Illumina 250-mers, or $\sim 1\ \mu\text{m}$ long strands) | Binary evanescent-field step: fluorescent $10\text{-mer}$ placed $200\text{ nm}$ from end (outside TIRF range) relaxes to **$< 1\text{ nm}$** upon cleavage |
| **Readout Amplification** | Periodic magnetic scooping ($\sim 1\text{ hr}^{-1}$), $10^9\times$ PCR amplification, high-throughput sequencing | Direct Total Internal Reflection Fluorescence (TIRF) single-molecule imaging |

---

## 2. Sub-Micron Radiation Transport & Elastic Recoil Kinematics

### 2.1 Non-Relativistic Elastic Recoil Energy and Impedance Matching
For a projectile of mass $m_\chi$ (in $\text{GeV}/c^2$) and speed $v$ scattering elastically at center-of-mass angle $\theta \in [0, \pi]$ off a stationary target nucleus of mass $M$ (in $\text{GeV}/c^2$):

$$\mu = \frac{m_\chi M}{m_\chi + M}, \qquad E_{\text{nr}}(\theta) = \frac{\mu^2}{M} v^2 (1 - \cos\theta), \qquad E_{\max} = \frac{2\mu^2}{M} v^2, \qquad \langle E_{\text{nr}} \rangle = \frac{1}{2} E_{\max} = \frac{\mu^2}{M} v^2.$$

With $c = 2.99792458 \times 10^5\text{ km/s}$ (approximated as $3.0 \times 10^5\text{ km/s}$ in Table 1 of Drukier et al., 2015) and $1\text{ GeV} = 10^6\text{ keV}$, the kinematic energy transfer efficiency relative to projectile kinetic energy $E_\chi = \frac{1}{2} m_\chi v^2$ is:

$$\eta_{\text{kin}}(m_\chi, M) = \frac{E_{\max}}{E_\chi} = \frac{4 m_\chi M}{(m_\chi + M)^2} \in (0, 1],$$

which reaches $\eta_{\text{kin}} = 1$ when $M = m_\chi$. Given a detector energy threshold $E_{\text{th}}$, the minimum projectile velocity required to deposit $E_{\text{th}}$ is:

$$v_{\min}(E_{\text{th}}) = c \sqrt{\frac{M E_{\text{th}}}{2 \mu^2}}.$$

### 2.2 Verified Benchmark Table and Source-Paper Errata ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), Table 1, p. 17)
At $v = 300\text{ km/s}$ ($\beta = v/c = 10^{-3}$):

| Projectile Mass $m_\chi\ [\text{GeV}]$ | Target Element | Target Mass $M\ [\text{GeV}]$ | Reduced Mass $\mu\ [\text{GeV}]$ | Mean Recoil $\langle E_{\text{nr}} \rangle\ [\text{keV}]$ | SRIM Slab Range $r_{\text{stop}}\ [\text{nm}]$ | $v_{\min}(0.5\text{ keV})\ [\text{km/s}]$ | $v_{\min}(5\text{ keV})\ [\text{km/s}]$ | $v_{\min}(10\text{ keV})\ [\text{km/s}]$ |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `400.0` | $\text{W}$ | `171.3` | `119.94` | `84.0` (`83.98`) | `10.2` | `16.4` | `51.8` | `73.2` |
| `200.0` | $\text{W}$ | `171.3` | `92.27` | `49.7` (`49.71`) | `7.1` | `21.3` | `67.3` | `95.2` |
| `100.0` | $\text{Sn}$ | `110.6` | `52.52` | `24.9` (`24.94`) | `11.4` | `30.0` | `95.0` | `134.3` |
| `50.0` | $\text{Cu}$ | `59.2` | `27.11` | `12.4` (`12.41`) | `5.6` | `42.6` | `134.6` | `190.4` |
| `200.0` | $\text{Au}$ | `183.5` | `95.70` | `49.9` (`49.91`) | `7.3` (in Au foil) | `21.2` | `67.1` | `94.9` |
| `1000.0` | $\text{Au}$ | `183.5` | `155.05` | `131.0` (`131.01`) | `14.0` (in Au foil) | `13.1` | `41.4` | `58.6` |

- **Documented Source Errata in Drukier et al. (2015)**:
  1. In Table 1 (p. 17), the first $v_{\min}$ row (`16.4, 21.3, 30.0, 42.6 km/s`) is mislabeled `E_th = 10 keV`; by $v_{\min} \propto \sqrt{E_{\text{th}}}$, it corresponds to $E_{\text{th}} = 0.5\text{ keV}$.
  2. In the Table 1 caption (p. 17), copper is described as `for a m_chi = 5 GeV WIMP`; the actual value used in the column header and Appendix text (p. 16) is $m_\chi = 50\text{ GeV}$.
  3. On page 12, intrinsic potassium radioactivity is misprinted as `K^41` (which is stable); page 13 correctly specifies ${}^{40}\text{K}$.

---

## 3. Energy Deposition ($dE/dx$), Strand Scission Probability, and Secondary Cascades

### 3.1 Continuous Electronic & Nuclear Stopping Power (`SRIM` / `ASTAR` / `Geant4-DNA`)
Along a recoil or background particle trajectory $\mathbf{r}(s)$, total linear energy transfer is the sum of electronic (ionization/excitation) and nuclear (elastic knock-on) stopping powers:

$$-\frac{dE}{ds}(E; Z_{\text{proj}}, M_{\text{proj}}, \text{medium}) = S_e(E) + S_n(E).$$

In low-energy heavy-ion recoil ($1\text{ to }131\text{ keV}$ Au nuclei), Lindhard-Scharff-Schiott (LSS) nuclear stopping $S_n(E)$ dominates in the metal foil, reducing a $50\text{ keV}$ Au recoil originated at $2.5\text{ nm}$ depth in a $5\text{ nm}$ Au foil to a mean exit energy of $E_{\text{exit}} = 27.5\text{ keV}$ at mean angular deflection $\langle\psi\rangle = 17.1^\circ$ ($E_{\text{exit}} = 110\text{ keV}$, $\langle\psi\rangle = 10.9^\circ$ for a $1\text{ TeV}$ WIMP recoil starting at $131\text{ keV}$).

### 3.2 Stochastic Single-Strand Cleavage Model
Rather than assuming deterministic strand severing, the probability $P_{\text{scission}}(\Delta E_i)$ that a single-stranded nucleic acid (ssDNA or ssRNA) backbone is severed when a particle deposits local energy $\Delta E_i$ within the strand interaction cylinder (radius $r_{\text{strand}} \approx 1.0\text{ nm}$) is modeled as a thresholded Hill / Poisson activation function parameterized by the characteristic backbone scission energy $E_{\text{scission}} \approx 10.0\text{ eV}$ ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), p. 8; O'Hare et al., 2022):

$$P_{\text{scission}}(\Delta E_i; E_{\text{scission}}, m) = 1 - \exp\left(-\left(\frac{\max(\Delta E_i - E_{\text{min}}, 0)}{E_{\text{scission}} - E_{\text{min}}}\right)^m\right),$$

where $E_{\text{min}} \approx 4.0\text{ to }6.0\text{ eV}$ is the phosphodiester bond dissociation threshold in dry/gas-phase $\text{He}/\text{N}_2$ and $m \ge 1$ is the steepness parameter. For double-stranded DNA (dsDNA), two proximate single-strand breaks on opposite strands within $\Delta b \le 10\text{ bp}$ are required for double-strand cleavage; otherwise a single $10\text{ eV}$ hit produces only a non-severing nick ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), Footnote 4, p. 8).

### 3.3 Primary Recoil vs. Secondary Knock-On Cascade Separation
From SRIM simulations ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), p. 11) assuming simple-packed ssNA strands at lateral pitch $a_{xy} = 10\text{ nm}$:
- **Primary Au Recoil ($200\text{ GeV}$ WIMP, $E_{\text{exit}} = 27.5\text{ keV}$)**: Stops in $L_{\text{primary}} \approx 2.55\ \mu\text{m}$ of ssNA curtain, severing $N_{\text{primary}} \approx 255$ strands.
- **Primary Au Recoil ($1000\text{ GeV}$ WIMP, $E_{\text{exit}} = 110\text{ keV}$)**: Stops in $L_{\text{primary}} \approx 5.83\ \mu\text{m}$ of ssNA curtain, severing $N_{\text{primary}} \approx 583$ strands.
- **Secondary Knock-On Au Cascades**: Each primary Au recoil ejects an average of $\langle N_{\text{sec}} \rangle = 21.3$ ($21.4$) secondary Au atoms from the foil with mean kinetic energy $\langle E_{\text{sec}} \rangle = 63\text{ eV}$ ($89\text{ eV}$), each traversing only $N_{\text{sec,strands}} \approx 18$ ($20$) ssNA strands ($\sim 180\text{ to }200\text{ nm}$).
- **Multi-Layer Stopping Discrimination**: A $5\text{ MeV}$ background $\alpha$-particle has an ASTAR stopping range of $\sim 30\ \mu\text{m}$ in Mylar ($10\ \mu\text{m}$ in Au), punching through $N_{\text{pages}} \approx 30$ sequential $1\ \mu\text{m}$-Mylar modules, whereas a $10\text{ keV}$ Au recoil stops in $20\text{ nm}$ of Mylar ($N_{\text{pages}} = 1$).

---

## 4. First-Principles Radiochemical Background Model in Depleted RNA

For a detector mass $m_{\text{RNA}}$ (in $\text{kg}$) of bacterial 23S-rRNA with mean nucleotide molar mass $\bar{M}_{\text{nt}} \approx 320\text{ g/mol}$ ($N_{\text{nt}}(0.1\text{ kg}) \approx 1.88 \times 10^{23}$ to $2.0 \times 10^{23}$ nucleotides) and $\bar{n}_{\text{C}} = 9.5$ carbon atoms per nucleotide ([1206.6809v2.pdf](file:///Users/aurascoper/Downloads/1206.6809v2.pdf), p. 13):

1. **${}^{40}\text{K}$ Counter-Ion Decay Rate** ($t_{1/2,40} = 1.25 \times 10^9\text{ yr}$, natural abundance $f_{40} = 1.2 \times 10^{-4}$, $\text{Na}^+:\text{K}^+$ purification ratio $R_{\text{Na:K}} = 10^7$):
   $$N_{{}^{40}\text{K}}(m_{\text{RNA}}) = N_{\text{nt}}(m_{\text{RNA}}) \cdot \frac{f_{40}}{R_{\text{Na:K}}}, \qquad \lambda_{40} = \frac{\ln 2}{t_{1/2,40} \times 365.25\text{ days/yr}} \approx 1.5182 \times 10^{-12}\text{ day}^{-1},$$
   $$R_{{}^{40}\text{K}}(m_{\text{RNA}}) = N_{{}^{40}\text{K}}(m_{\text{RNA}}) \cdot \lambda_{40}.$$
   At $N_{\text{nt}}(0.1\text{ kg}) = 2.0 \times 10^{23}$ and $R_{\text{Na:K}} = 10^7$, $N_{{}^{40}\text{K}} = 2.4 \times 10^{12}$ atoms, yielding $R_{{}^{40}\text{K}} = 3.64\text{ decays/day}$ from first principles (reported as an order-of-magnitude estimate of $\sim 6\text{ decays/day}$ in Drukier et al., 2015, p. 13, alongside a factor-of-10 arithmetic misprint writing "$2 \times 10^{11}$ atoms").
2. **${}^{14}\text{C}$ Petrochemical Depletion Decay Rate** ($t_{1/2,14} = 5730\text{ yr}$, Borexino old-carbon ratio $f_{14} = {}^{14}\text{C}/{}^{12}\text{C} = 1.94 \times 10^{-18}$ from Alimonti et al., 1998):
   $$N_{{}^{14}\text{C}}(m_{\text{RNA}}) = \bar{n}_{\text{C}} \cdot N_{\text{nt}}(m_{\text{RNA}}) \cdot f_{14}, \qquad \lambda_{14} = \frac{\ln 2}{t_{1/2,14} \times 365.25\text{ days/yr}} \approx 3.3119 \times 10^{-7}\text{ day}^{-1},$$
   $$R_{{}^{14}\text{C}}(m_{\text{RNA}}) = N_{{}^{14}\text{C}}(m_{\text{RNA}}) \cdot \lambda_{14}.$$
   At $N_{\text{nt}}(0.1\text{ kg}) = 2.0 \times 10^{23}$, $N_{{}^{14}\text{C}} = 3.686 \times 10^6$ atoms, yielding $R_{{}^{14}\text{C}} = 1.22\text{ decays/day}$ ($\sim 2\text{ decays/day}$ in Drukier et al., 2015, p. 13).

---

## 5. Voxelized Track Reconstruction and Readout Noise Model (O'Hare et al., 2022)

When reconstructing a 3D recoil vector $\hat{\mathbf{u}}_{\text{rec}}$ from a set of $K$ sequenced fragment break coordinates $\{(I_k, J_k, z_k)\}_{k=1}^K$:
1. **Anisotropic Voxel Quantization Noise**:
   Each break $k$ has uniform transverse quantization uncertainty over the bundle barcode square $\Delta x, \Delta y \sim \mathcal{U}(-L_{\text{bundle}}/2, +L_{\text{bundle}}/2)$ ($L_{\text{bundle}} = 1000\text{ nm}$ in Architecture A, or $10\text{ nm}$ if single-dot barcoding is achieved) and axial uncertainty $\sigma_z = \sqrt{(\delta z_{\text{base}})^2 + \sigma_{\text{thermal}}^2(z_k)}$ where $\delta z_{\text{base}} \approx 0.7\text{ nm}$ and $\sigma_{\text{thermal}}(z_k)$ accounts for entropic/Brownian strand slack prior to cleavage.
2. **PCR Dropout & Chimerism Noise**:
   Each severed fragment is recovered and amplified with collection-plus-PCR efficiency $\epsilon_{\text{readout}} \in (0, 1]$ and false-positive background cleavage rate $\lambda_{\text{bg}}\ [\text{breaks}/\mu\text{m}^3/\text{hr}]$.
3. **Weighted Total Least Squares (WTLS) Axis & Head/Tail Reconstruction**:
   Because $\sigma_{xy}^2 \gg \sigma_z^2$ under $1\ \mu\text{m}$ bundle barcoding, track fitting must weight coordinates by $\Sigma_k^{-1} = \text{diag}(\sigma_x^{-2}, \sigma_y^{-2}, \sigma_z^{-2})$, while head-to-tail sense ($\text{sgn}(\hat{\mathbf{u}}_{\text{rec}} \cdot \hat{\mathbf{z}})$) is determined by the monotonic decrease in $dE/ds$ (strand-break density per unit path length) toward the stopping end of the track and by the asymmetric Mylar-Au-ssNA layer ordering.

---

## 6. Mandatory Scientific Consistency Corrections to Commit `4498ead` Before Extraction

In commit `4498eadcdf79eb58376cc278bca5d2c38e5eacf8` ([backends.jl](file:///Users/aurascoper/.gemini/antigravity/scratch/NeuroARC.jl/src/backends.jl#L1841-L1948)), two scientific consistency defects were introduced that must be corrected when extracting the detector model into the standalone module `RadiationNucleicAcidDamage`:

### 6.1 ${}^{40}\text{K}$ Atom-Count ($8.33 \times 10^5$-Fold Error) and Rate Consistency
- **Defect in `4498ead` ([backends.jl](file:///Users/aurascoper/.gemini/antigravity/scratch/NeuroARC.jl/src/backends.jl#L1849-L1850))**:
  Line 1849 computed `n_k40_atoms = n_nucleotides * (1.0e7 / Float64(na_to_k_ratio)) * (k40_abundance / 1.2e-11) * 1.0e-12`, which evaluated to $2.0 \times 10^{18}$ atoms for $0.1\text{ kg}$ RNA (an $8.33 \times 10^5$-fold error over the true $2.4 \times 10^{12}$ atoms), while line 1850 independently hardcoded `k40_decays_per_day = 6.0 * m_scale * (1.0e7 / Float64(na_to_k_ratio))`.
- **Required Fix**:
  1. Compute $N_{{}^{40}\text{K}} = N_{\text{nt}} \cdot (f_{40} / R_{\text{Na:K}}) = 2.0 \times 10^{23} \times (1.2 \times 10^{-4} / 10^7) = 2.4 \times 10^{12}$ atoms for $0.1\text{ kg}$ RNA.
  2. Derive the daily decay rate directly from $N_{{}^{40}\text{K}}$ and $\lambda_{40} = \ln(2) / (1.25 \times 10^9 \times 365.25)\ \text{day}^{-1} \approx 1.518198 \times 10^{-12}\ \text{day}^{-1}$, yielding $R_{{}^{40}\text{K}} = N_{{}^{40}\text{K}} \cdot \lambda_{40} \approx 3.643675\text{ decays/day}$.
  3. Record `paper_approx_k40_decays_per_day = 6.0 * m_scale * (1.0e7 / Float64(na_to_k_ratio))` and `paper_printed_k40_atoms_typo = 2.0e11 * m_scale * (1.0e7 / Float64(na_to_k_ratio))` only as explicit literature-comparison metadata fields, and enforce a unit-test invariant `isapprox(res.k40_decays_per_day, res.k40_atoms * res.lambda_k40_per_day; rtol=1e-12)`.

### 6.2 Separation of Detector Geometries and Population-Level Directional Asymmetry
- **Defect in `4498ead` ([backends.jl](file:///Users/aurascoper/.gemini/antigravity/scratch/NeuroARC.jl/src/backends.jl#L1883-L1948))**:
  `evaluate_ssna_track_quarantine` combined the hanging-curtain geometry (`pages_traversed == 1` and `severed_strands >= min_primary_strands`) with the separate stretched 23S-rRNA coverslip geometry (`0.0 <= fluorophore_z_nm <= 1.0`), and applied `head_tail_ratio >= 5.0` as a single-track gate even though the $\sim 10:1$ backward-to-forward WIMP recoil asymmetry in Drukier et al. (2015) is a **population-level ensemble observable** across $N \approx 30\text{ to }100$ candidate events.
- **Required Fix**:
  Provide three separate, physically distinct functions in `RadiationNucleicAcidDamage`:
  1. `evaluate_curtain_track_candidate(spec::HangingCurtainDetectorSpec, pages_traversed::Int, severed_strands::Int; forward_hemi::Bool = true)`: Per-track gate for Architecture A (single-foil containment `pages_traversed == 1`, primary vs. secondary cascade strand count `severed_strands >= spec.min_primary_strands`, and forward Mylar-to-Au-to-ssNA hemisphere check).
  2. `evaluate_tirf_coverslip_candidate(spec::StretchedRRNACoverslipSpec, fluorophore_z_nm::Real, intact_control_z_nm::Real)`: Per-molecule optical readout gate for Architecture B ($2,904\text{-nt}$ stretched 23S-rRNA where cleavage drops the $200\text{ nm}$ fluorophore into the $\le 1.0\text{ nm}$ TIRF evanescent zone).
  3. `evaluate_population_directional_asymmetry(backward_recoil_count::Int, forward_recoil_count::Int; min_asymmetry_ratio::Real = 5.0, min_total_events::Int = 30)`: Population-level statistical gate evaluating sample head-to-tail recoil asymmetry across an ensemble of reconstructed tracks.

