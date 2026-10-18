"""
Prebiotic replicator chemostat simulation with log-simplex stability.

This module models phenomenological replicator dynamics in an open continuous chemostat.
To prevent exponential divergence, numerical stiffness blowups, and negative
concentrations, dynamics are integrated in log-simplex coordinates:
- Relative frequencies x_i evolve via d(ln x_i)/dt = r_i - r_mean.
- Population density N evolves via d(ln N)/dt = r_mean - D.
- Substrate concentration S is constrained by chemostat inflow/outflow fluxes.

Note on scientific claims:
The two-phase protocol measures history-dependent compositional persistence
(ecological attractor divergence in a differential population model). It does not
model full biochemical mass-action stoichiometry or establish an internal
molecular-memory mechanism.
"""

from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple
import numpy as np


@dataclass
class ReplicatorSpecies:
    """
    Molecular replicator parameter specification.
    
    Attributes:
        name: Identifier for the replicator variant.
        k_cat: Maximum catalytic replication rate (1/time).
        k_m: Michaelis constant for monomer substrate affinity.
        t_opt: Optimal catalytic temperature in Celsius.
        t_width: Thermal tolerance width (standard deviation in Celsius).
        decay_rate: Intrinsic abiotic hydrolysis/degradation rate.
    """
    name: str
    k_cat: float
    k_m: float = 1.0
    t_opt: float = 65.0
    t_width: float = 15.0
    decay_rate: float = 0.01

    def replication_rate(self, s: float, t: float) -> float:
        """Calculate temperature- and substrate-dependent replication rate."""
        # Thermal inactivation curve (Gaussian around optimal folding temperature)
        t_factor = np.exp(-0.5 * ((t - self.t_opt) / self.t_width) ** 2)
        # Michaelis-Menten substrate kinetics
        s_factor = s / (self.k_m + s) if s > 0 else 0.0
        return float(self.k_cat * t_factor * s_factor - self.decay_rate)


@dataclass
class ChemostatConfig:
    """
    Chemostat physical environment parameters.
    
    Attributes:
        dilution_rate: Chemostat dilution / washout rate D (1/time).
        substrate_inflow: Feed concentration S0 of activated monomers.
        stoichiometry: Monomer consumed per replication unit.
    """
    dilution_rate: float = 0.10
    substrate_inflow: float = 10.0
    stoichiometry: float = 0.50


@dataclass
class ChemostatHistory:
    """Simulation trajectory output container."""
    times: np.ndarray
    frequencies: np.ndarray  # Shape: (T, K)
    total_population: np.ndarray  # Shape: (T,)
    substrate: np.ndarray  # Shape: (T,)
    temperatures: np.ndarray  # Shape: (T,)
    species_names: List[str]


class Chemostat:
    """
    Simulates prebiotic replicator competition in an open chemostat.
    """

    def __init__(self, species: List[ReplicatorSpecies], config: Optional[ChemostatConfig] = None):
        if not species:
            raise ValueError("Must provide at least one replicator species.")
        self.species = species
        self.config = config or ChemostatConfig()
        self.k = len(species)

    @staticmethod
    def _softmax(u: np.ndarray) -> np.ndarray:
        """Numerically stable softmax transformation."""
        m = np.max(u)
        exp_u = np.exp(u - m)
        return exp_u / np.sum(exp_u)

    def _derivatives(
        self,
        u: np.ndarray,
        log_n: float,
        s: float,
        temp: float
    ) -> Tuple[np.ndarray, float, float]:
        """
        Compute derivatives for log-simplex state (u, log_n, s).
        """
        x = self._softmax(u)
        n = np.exp(log_n)

        # Compute replication rates for each species
        rates = np.array([sp.replication_rate(s, temp) for sp in self.species])
        r_mean = float(np.sum(x * rates))

        # Log-frequency derivative: d(u_i)/dt = r_i - r_mean
        du_dt = rates - r_mean

        # Log-density derivative: d(log N)/dt = r_mean - D
        dlogn_dt = r_mean - self.config.dilution_rate

        # Substrate derivative: dS/dt = D * (S0 - S) - gamma * N * max(0, r_mean)
        eff_replication = max(0.0, r_mean)
        ds_dt = self.config.dilution_rate * (self.config.substrate_inflow - s) - (
            self.config.stoichiometry * n * eff_replication
        )

        return du_dt, dlogn_dt, ds_dt

    def simulate(
        self,
        init_frequencies: np.ndarray,
        init_population: float,
        init_substrate: float,
        duration: float,
        dt: float = 0.05,
        temp_schedule: Optional[Callable[[float], float]] = None
    ) -> ChemostatHistory:
        """
        Integrate the chemostat ODE using 4th-order Runge-Kutta.

        Args:
            init_frequencies: Initial frequency distribution on simplex (length K).
            init_population: Initial total biomass density N0 > 0.
            init_substrate: Initial monomer concentration S0 >= 0.
            duration: Total simulation time.
            dt: Time step size.
            temp_schedule: Optional function mapping time t -> temperature in Celsius.

        Returns:
            ChemostatHistory containing full state trajectories.
        """
        if temp_schedule is None:
            temp_schedule = lambda t: 65.0

        n_steps = int(np.ceil(duration / dt))
        times = np.zeros(n_steps + 1)
        freq_hist = np.zeros((n_steps + 1, self.k))
        pop_hist = np.zeros(n_steps + 1)
        sub_hist = np.zeros(n_steps + 1)
        temp_hist = np.zeros(n_steps + 1)

        # Initialize log state
        norm_freq = np.asarray(init_frequencies, dtype=float)
        norm_freq = np.clip(norm_freq, 1e-12, None)
        norm_freq = norm_freq / np.sum(norm_freq)
        u = np.log(norm_freq)

        log_n = float(np.log(max(1e-12, init_population)))
        s = float(max(0.0, init_substrate))

        # Record t=0
        times[0] = 0.0
        freq_hist[0] = norm_freq
        pop_hist[0] = np.exp(log_n)
        sub_hist[0] = s
        temp_hist[0] = temp_schedule(0.0)

        for step in range(n_steps):
            t = step * dt
            t_mid = t + 0.5 * dt
            t_next = t + dt

            temp_1 = temp_schedule(t)
            temp_2 = temp_schedule(t_mid)
            temp_4 = temp_schedule(t_next)

            # RK4 Stage 1
            du1, dln1, ds1 = self._derivatives(u, log_n, s, temp_1)

            # RK4 Stage 2
            u2 = u + 0.5 * dt * du1
            ln2 = log_n + 0.5 * dt * dln1
            s2 = max(0.0, s + 0.5 * dt * ds1)
            du2, dln2, ds2 = self._derivatives(u2, ln2, s2, temp_2)

            # RK4 Stage 3
            u3 = u + 0.5 * dt * du2
            ln3 = log_n + 0.5 * dt * dln2
            s3 = max(0.0, s + 0.5 * dt * ds2)
            du3, dln3, ds3 = self._derivatives(u3, ln3, s3, temp_2)

            # RK4 Stage 4
            u4 = u + dt * du3
            ln4 = log_n + dt * dln3
            s4 = max(0.0, s + dt * ds3)
            du4, dln4, ds4 = self._derivatives(u4, ln4, s4, temp_4)

            # Update state
            u = u + (dt / 6.0) * (du1 + 2 * du2 + 2 * du3 + du4)
            log_n = log_n + (dt / 6.0) * (dln1 + 2 * dln2 + 2 * dln3 + dln4)
            s = max(0.0, s + (dt / 6.0) * (ds1 + 2 * ds2 + 2 * ds3 + ds4))

            # Store records
            times[step + 1] = t_next
            freq_hist[step + 1] = self._softmax(u)
            pop_hist[step + 1] = np.exp(log_n)
            sub_hist[step + 1] = s
            temp_hist[step + 1] = temp_4

        return ChemostatHistory(
            times=times,
            frequencies=freq_hist,
            total_population=pop_hist,
            substrate=sub_hist,
            temperatures=temp_hist,
            species_names=[sp.name for sp in self.species],
        )


def run_two_phase_compositional_persistence_experiment(
    exposure_duration: float = 100.0,
    challenge_duration: float = 100.0,
    dt: float = 0.05
) -> Tuple[float, ChemostatHistory, ChemostatHistory]:
    """
    Execute two-phase history-dependent compositional persistence experiment.

    Phase 1 (Divergent History):
    - Population 1 undergoes thermal regime 1 (hydrothermal vent regime: 85C).
    - Population 2 undergoes thermal regime 2 (mesophilic regime: 50C).

    Phase 2 (Matched Challenge E0):
    - Both populations placed in identical probe environment (E0: 68C, matched nutrients).
    - Observe differential response M = ||R(H1, E0) - R(H2, E0)||_1.

    Note: This measures compositional persistence of population frequencies in an
    ecological replicator dynamical model under matched challenge environments.
    It does not claim an internal biochemical molecular memory mechanism.

    Returns:
        Tuple of (persistence_divergence_metric, history_1_total, history_2_total).
    """
    # Define species ecology:
    # Species A: Thermostable ribozyme (optimal at 85C)
    # Species B: Mesophilic hairpin replicator (optimal at 50C)
    # Species C: Generalist slow replicator (optimal at 68C)
    sp_a = ReplicatorSpecies(name="Thermostable_A", k_cat=1.2, k_m=1.0, t_opt=85.0, t_width=10.0)
    sp_b = ReplicatorSpecies(name="Mesophilic_B", k_cat=1.2, k_m=1.0, t_opt=50.0, t_width=10.0)
    sp_c = ReplicatorSpecies(name="Generalist_C", k_cat=0.8, k_m=0.8, t_opt=68.0, t_width=20.0)

    chemostat = Chemostat([sp_a, sp_b, sp_c], ChemostatConfig(dilution_rate=0.10, substrate_inflow=10.0))

    init_freq = np.array([0.333, 0.333, 0.334])
    init_pop = 1.0
    init_sub = 5.0

    # Phase 1: Divergent exposure
    # History 1: Hot regime (85C)
    hist1_p1 = chemostat.simulate(
        init_frequencies=init_freq,
        init_population=init_pop,
        init_substrate=init_sub,
        duration=exposure_duration,
        dt=dt,
        temp_schedule=lambda t: 85.0
    )

    # History 2: Moderate regime (50C)
    hist2_p1 = chemostat.simulate(
        init_frequencies=init_freq,
        init_population=init_pop,
        init_substrate=init_sub,
        duration=exposure_duration,
        dt=dt,
        temp_schedule=lambda t: 50.0
    )

    # Phase 2: Matched challenge environment E0 (68C)
    final_freq_1 = hist1_p1.frequencies[-1]
    final_pop_1 = hist1_p1.total_population[-1]
    final_sub_1 = hist1_p1.substrate[-1]

    final_freq_2 = hist2_p1.frequencies[-1]
    final_pop_2 = hist2_p1.total_population[-1]
    final_sub_2 = hist2_p1.substrate[-1]

    # Matched probe environment at 68C
    hist1_p2 = chemostat.simulate(
        init_frequencies=final_freq_1,
        init_population=final_pop_1,
        init_substrate=final_sub_1,
        duration=challenge_duration,
        dt=dt,
        temp_schedule=lambda t: 68.0
    )

    hist2_p2 = chemostat.simulate(
        init_frequencies=final_freq_2,
        init_population=final_pop_2,
        init_substrate=final_sub_2,
        duration=challenge_duration,
        dt=dt,
        temp_schedule=lambda t: 68.0
    )

    # Compute trajectory-integrated divergence in matched environment E0
    # M = (1/T) \int || x_1(t) - x_2(t) ||_1 dt
    diff_norms = np.sum(np.abs(hist1_p2.frequencies - hist2_p2.frequencies), axis=1)
    persistence_metric = float(np.mean(diff_norms))

    return persistence_metric, hist1_p2, hist2_p2


# Backwards compatibility alias
run_two_phase_cybernetic_memory_experiment = run_two_phase_compositional_persistence_experiment
