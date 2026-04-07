function [results, run_info] = validate_fig5_sca_original(varargin)
if nargin == 1 && isstruct(varargin{1})
    run_cfg = pinching.experiments.build_run_config(varargin{1});
else
    run_cfg = pinching.experiments.build_run_config(varargin{:});
end

settings = default_fig5_settings();
params = pinching.model.default_params();
params = pinching.experiments.apply_param_overrides(params, run_cfg.param_overrides);
n_rpa_grid = resolve_fig5_rpa_grid(run_cfg, settings);
realizations = pinching.model.build_realizations(params);
paths = pinching.experiments.figure_output_paths(run_cfg, 5);
pinching.experiments.ensure_output_dirs(paths);
pinching.experiments.maybe_print_run_header(run_cfg, settings.run_header, params);

opts = run_cfg.sca_opts;
cvx_solver_name = pinching.experiments.configure_cvx_environment(opts);

fprintf('%s, M = %d, GammaReq = %.1f, MC = %d\n', ...
    settings.progress_label, ...
    params.M, params.gamma_req, params.mc_trials);

results = pinching.experiments.run_fig5_rpa_sweep(params, realizations, n_rpa_grid, opts);
results.cvx_solver = cvx_solver_name;
results.assumptions = settings.assumptions;

figure_files = plot_fig5(results, paths, settings);
write_summary(results, params, opts, paths.summary_file, settings);

save(paths.results_file, 'results', 'params', 'realizations', 'opts');
run_info = struct( ...
    'figure_id', 5, ...
    'results_file', paths.results_file, ...
    'summary_file', paths.summary_file, ...
    'figure_files', {figure_files});
save(paths.manifest_file, 'run_info');
end

function settings = default_fig5_settings()
settings = struct();
settings.run_header = 'Running Fig. 5 validation';
settings.progress_label = 'Validating Fig. 5 with the current SCA solver';
settings.n_rpa_grid = 2:2:12;
settings.plot_title = 'Fig. 5 Validation';
settings.summary_title = 'Fig. 5 validation summary';
settings.assumptions = [ ...
    "User/target locations are sampled uniformly over the serving area."; ...
    "Infeasible realizations contribute zero communication rate."; ...
    "The upper bound is computed by solving the same SCA model with gamma_req set to zero."; ...
    "When N changes, RPAs are re-distributed uniformly over the serving area."];
end

function n_rpa_grid = resolve_fig5_rpa_grid(run_cfg, settings)
default_run_cfg = pinching.experiments.default_run_config();
if isequal(run_cfg.fig5.n_rpa_grid, default_run_cfg.fig5.n_rpa_grid)
    n_rpa_grid = settings.n_rpa_grid;
else
    n_rpa_grid = run_cfg.fig5.n_rpa_grid;
end
end

function figure_files = plot_fig5(results, paths, settings)
n_rpa_grid = results.n_rpa_grid;
avg_rate = results.avg_rate;
figure_files = {fullfile(paths.figure_dir, 'fig5_sca_original_comparison.png')};

fig = figure('Color', 'w', 'Position', [100, 100, 1040, 560]);
hold on;
plot(n_rpa_grid, avg_rate(1, :), '-', 'LineWidth', 1.8, 'DisplayName', 'Upper bound (SCA)');
plot(n_rpa_grid, avg_rate(2, :), '-o', 'LineWidth', 1.8, 'MarkerSize', 5, 'DisplayName', 'Pinching (SCA)');
plot(n_rpa_grid, avg_rate(3, :), '--s', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Target-oriented');
plot(n_rpa_grid, avg_rate(4, :), '--d', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Midpoint');
plot(n_rpa_grid, avg_rate(5, :), '--^', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'User-centric');
plot(n_rpa_grid, avg_rate(6, :), '--x', 'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', 'Conventional');
xlabel('Number of RPAs');
ylabel('Communication Rate [bit/s/Hz]');
title(settings.plot_title);
grid on;
if numel(n_rpa_grid) > 1
    xlim([n_rpa_grid(1), n_rpa_grid(end)]);
end
legend('Location', 'eastoutside');
hold off;
exportgraphics(fig, figure_files{1}, 'Resolution', 220);
end

function write_summary(results, params, opts, summary_file, settings)
fid = fopen(summary_file, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '%s\n', settings.summary_title);
fprintf(fid, '%s\n\n', repmat('=', 1, strlength(settings.summary_title)));
fprintf(fid, 'MC trials: %d\n', params.mc_trials);
fprintf(fid, 'Pmax: %.2f W\n', params.Pmax);
fprintf(fid, 'GammaReq: %.2f\n', params.gamma_req);
fprintf(fid, 'RPA grid: %s\n', mat2str(results.n_rpa_grid));
fprintf(fid, 'CVX solver used: %s\n', results.cvx_solver);
fprintf(fid, 'SCA opts: max_iters=%d, tol=%g, seed_count=%d, precision=%s\n\n', ...
    opts.max_iters, opts.tol, opts.seed_count, opts.cvx_precision);

fprintf(fid, 'Assumptions:\n');
for i = 1:numel(settings.assumptions)
    fprintf(fid, '- %s\n', settings.assumptions(i));
end
fprintf(fid, '\n');

fprintf(fid, 'Average communication rate [bit/s/Hz]\n');
fprintf(fid, 'N\tupper_sca\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\n', ...
        results.n_rpa_grid(nidx), results.avg_rate(1, nidx), results.avg_rate(2, nidx), ...
        results.avg_rate(3, nidx), results.avg_rate(4, nidx), results.avg_rate(5, nidx), results.avg_rate(6, nidx));
end

fprintf(fid, '\nFeasibility ratio\n');
fprintf(fid, 'N\tupper_sca\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n', ...
        results.n_rpa_grid(nidx), results.feasible_ratio(1, nidx), results.feasible_ratio(2, nidx), ...
        results.feasible_ratio(3, nidx), results.feasible_ratio(4, nidx), results.feasible_ratio(5, nidx), results.feasible_ratio(6, nidx));
end

fprintf(fid, '\nAverage upper-bound SCA iterations\n');
fprintf(fid, 'N\titerations\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_rpa_grid(nidx), results.avg_upper_iterations(nidx));
end

fprintf(fid, '\nAverage upper-bound SCA iterations among successful runs\n');
fprintf(fid, 'N\titerations_success_only\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_rpa_grid(nidx), results.avg_upper_iterations_success_only(nidx));
end

fprintf(fid, '\nAverage pinching SCA iterations\n');
fprintf(fid, 'N\titerations\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_rpa_grid(nidx), results.avg_pinching_iterations(nidx));
end

fprintf(fid, '\nAverage pinching SCA iterations among successful runs\n');
fprintf(fid, 'N\titerations_success_only\n');
for nidx = 1:numel(results.n_rpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_rpa_grid(nidx), results.avg_pinching_iterations_success_only(nidx));
end

fprintf(fid, '\nUpper-bound SCA status counts\n');
fprintf(fid, 'status\tcount\n');
for sidx = 1:height(results.upper_status_summary)
    fprintf(fid, '%s\t%d\n', results.upper_status_summary.status(sidx), results.upper_status_summary.count(sidx));
end

fprintf(fid, '\nPinching SCA status counts\n');
fprintf(fid, 'status\tcount\n');
for sidx = 1:height(results.pinching_status_summary)
    fprintf(fid, '%s\t%d\n', results.pinching_status_summary.status(sidx), results.pinching_status_summary.count(sidx));
end
end
