# Multi-Waveguide Pinching Antennas for ISAC -reproduction

This repository is a small MATLAB research project centered on pinching-antenna ISAC experiments. The current codebase is organized around package-based APIs for custom scenarios, validation sweeps, and the underlying SCA solver.

This implementation is based on the research: *Mao, W., Lu, Y., Xu, Y., Ai, B., Dobre, O. A., & Niyato, D. 

[[2505.24307\] Multi-Waveguide Pinching Antennas for ISAC](https://arxiv.org/abs/2505.24307)

## Layout

- `+pinching/+api`: public entry points and config builders for scenario runs, validation sweeps, and direct joint solving.
- `+pinching/+experiments`: sweep orchestration, output helpers, CVX setup, statistics, and method dispatch.
- `+pinching/+model`: shared physical-layer model, channel construction, beamforming, and utility functions.
- `+pinching/+schemes`: reusable scheme-level optimizers and fixed-layout baselines.
- `+pinching/+sca`: the CVX-based SCA solver.
- `outputs/`: saved `.mat` outputs, summaries, and exported plot images grouped by run tag.
- `scripts/`: usage notes and legacy CLI wrappers.
- Root wrappers such as `run_scenario.m` and `solve_joint_isac.m`: thin compatibility shims into `pinching.api`.

## Supported Entry Points

Run a custom scenario directly from the MATLAB command window:

```matlab
run_scenario( ...
    'M', 8, ...
    'N', 4, ...
    'Pmax', 12, ...
    'gamma_req', 4, ...
    'xu', 6, 'yu', 8, ...
    'xt', -5, 'yt', 12, ...
    'methods', {'sca', 'proposed_pinching', 'midpoint', 'conventional'}, ...
    'output_tag', 'custom_case_01')
```

Run a single paper-style figure validation through the root entry:

```matlab
validate_fig3_sca_original('M', 8, 'mc_trials', 40, 'output_tag', 'fig3_m8')
validate_fig5_sca_original('n_rpa_grid', 2:2:10, 'output_tag', 'fig5_custom')
```

Run a configurable validation sweep through the package API:

```matlab
pinching.api.run_validation( ...
    'name', 'Custom Fig. 3 Style Validation Sweep', ...
    'result_name', 'fig3_like_rates', ...
    'figure_name', 'fig3_like_plot', ...
    'sweep_param', 'Pmax', ...
    'sweep_values', 4:2:16, ...
    'M', 8, ...
    'mc_trials', 40, ...
    'output_tag', 'fig3_m8_p12')
```

Solve a single joint layout/beamforming problem and inspect the structured result:

```matlab
solution = solve_joint_isac( ...
    'M', 8, ...
    'N', 4, ...
    'Pmax', 12, ...
    'gamma_req', 4, ...
    'xu', 6, 'yu', 8, ...
    'xt', -5, 'yt', 12);
```

Run several paper-style figure validations by calling the desired entries:

```matlab
validate_fig3_sca_original('output_tag', 'fig3_batch')
validate_fig4_sca_original('output_tag', 'fig4_batch')
validate_fig6_sca_original('output_tag', 'fig6_batch')
```

## Which Entry To Use

Use `validate_fig2_sca_original(...)` through `validate_fig6_sca_original(...)` when you want to validate paper figures.

```matlab
validate_fig3_sca_original
validate_fig5_sca_original('n_rpa_grid', 2:2:10, 'mc_trials', 40, 'output_tag', 'fig5_custom')
validate_fig3_sca_original('output_tag', 'paper_fig3')
validate_fig4_sca_original('output_tag', 'paper_fig4')
```

- `validate_figN_sca_original(...)` runs one paper-style figure validation such as Fig. 3 or Fig. 5.
- Each figure file keeps its own default sweep settings so you can edit the figure script directly when needed.
- Use these when your goal is "check the paper-style curve or table" rather than inspect one single scenario.

Use `run_scenario(...)` when you want to validate or compare methods on one specific scenario you choose yourself.

```matlab
[experiment, run_info] = run_scenario( ...
    'M', 8, ...
    'N', 4, ...
    'Pmax', 12, ...
    'gamma_req', 4, ...
    'xu', 6, 'yu', 8, ...
    'xt', -5, 'yt', 12, ...
    'methods', {'sca', 'proposed_pinching', 'midpoint', 'conventional'}, ...
    'output_tag', 'custom_case');
```

- `run_scenario(...)` fixes one user/target layout and compares one or more methods on that exact case.
- It is the best entry point when you want to sanity-check behavior, inspect feasibility, or test how methods compare on a hand-picked scene.
- It writes a compact results struct, a summary text file, and an optional bar chart under `outputs/custom/<output_tag>/`.

Use `solve_joint_isac(...)` when you want one direct SCA solve for one scenario, without the extra comparison/report wrapper.

```matlab
solution = solve_joint_isac( ...
    'M', 8, ...
    'N', 4, ...
    'Pmax', 12, ...
    'gamma_req', 4, ...
    'xu', 6, 'yu', 8, ...
    'xt', -5, 'yt', 12);

disp(solution.summary.headline)
```

- `solve_joint_isac(...)` runs only the SCA solver.
- It is the best entry point when you want the optimized layout, solver status, iteration count, and metrics for one case.
- Use it when your goal is "solve this one instance" rather than "compare methods" or "validate a whole figure".

The same entry points work from the command line:

```powershell
matlab -batch "validate_fig4_sca_original('gamma_req',2,'fig4_gamma_grid',0:0.5:6,'mc_trials',30,'output_tag','fig4_sweep')"
matlab -batch "validate_fig6_sca_original('n_tpa_grid',2:2:12,'mc_trials',40,'output_tag','fig6_run')"
matlab -batch "pinching.api.run_validation('name','Batch Sweep','sweep_param','Pmax','sweep_values',4:2:16,'M',8,'mc_trials',40,'output_tag','batch_run')"
```

See [scripts/USAGE.md](/C:/Users/21416/Desktop/project/scripts/USAGE.md) for more examples.

## Call Flow

```text
run_scenario / solve_joint_isac / validate_fig*_sca_original / pinching.api.run_validation
    -> pinching.api.build_*_config / build_validation_config
    -> pinching.experiments (for sweeps/method dispatch) or direct scenario runner
    -> pinching.sca / pinching.schemes
    -> pinching.model
    -> outputs/
```

## Design Notes

- The actively supported public surface is `pinching.api.*`, plus the root wrappers that already forward into `pinching.api`.
- Shared math and channel code lives in package functions so new experiments can reuse one model layer.
- `run_scenario(...)` is scenario-driven: you specify antenna counts, coordinates, constraints, and methods, and the solver stack is handled internally.
- `pinching.api.run_validation(...)` is sweep-driven: you choose the sweep variable and values, and the runner handles scenario generation, per-method evaluation, aggregation, and plotting.
- The root `validate_fig*_sca_original` files are supported figure-validation entry points built on top of the shared package implementation.
- Default custom-scenario outputs go under `outputs/custom/<output_tag>/`; default validation outputs go under `outputs/validations/<output_tag>/`.
- Figure-style runs keep writing under `outputs/<output_tag>/figX/` so older result layouts stay familiar.
