function [results, run_info] = validate_fig6_sca_original(varargin)
if nargin == 1 && isstruct(varargin{1})
    run_cfg = pinching.experiments.build_run_config(varargin{1});
else
    run_cfg = pinching.experiments.build_run_config(varargin{:});
end

settings = default_fig6_settings();
params = pinching.model.default_params();
params = pinching.experiments.apply_param_overrides(params, run_cfg.param_overrides);
n_tpa_grid = resolve_fig6_tpa_grid(run_cfg, settings);
realizations = pinching.model.build_realizations(params);
paths = pinching.experiments.figure_output_paths(run_cfg, 6);
pinching.experiments.ensure_output_dirs(paths);
pinching.experiments.maybe_print_run_header(run_cfg, settings.run_header, params);

opts = run_cfg.sca_opts;
cvx_solver_name = pinching.experiments.configure_cvx_environment(opts);

fprintf('%s, N = %d, GammaReq = %.1f, MC = %d\n', ...
    settings.progress_label, ...
    params.N, params.gamma_req, params.mc_trials);

results = pinching.experiments.run_standard_sweep( ...
    params, realizations, n_tpa_grid, @apply_tpa_count, opts, settings.context_prefix, settings.sweep_name);
results.n_tpa_grid = n_tpa_grid;
results.cvx_solver = cvx_solver_name;
results.assumptions = settings.assumptions;

figure_files = plot_fig6(results, paths, settings);
write_summary(results, params, opts, paths.summary_file, settings);

save(paths.results_file, 'results', 'params', 'realizations', 'opts');
run_info = struct( ...
    'figure_id', 6, ...
    'results_file', paths.results_file, ...
    'summary_file', paths.summary_file, ...
    'figure_files', {figure_files});
save(paths.manifest_file, 'run_info');
end

function params_run = apply_tpa_count(params, tpa_count)
params_run = params;
params_run.M = tpa_count;
params_run.yT = (1:params_run.M) * params_run.W / (params_run.M + 1);
end

function settings = default_fig6_settings()
settings = struct();
settings.run_header = 'Running Fig. 6 validation';
settings.progress_label = 'Validating Fig. 6 with the current SCA solver';
settings.context_prefix = 'Fig. 6';
settings.sweep_name = 'M';
settings.n_tpa_grid = 2:2:12;
settings.plot_title = 'Fig. 6 Validation';
settings.summary_title = 'Fig. 6 validation summary';
settings.assumptions = [ ...
    "User/target locations are sampled uniformly over the serving area."; ...
    "Infeasible realizations contribute zero communication rate."; ...
    "The pinching curve uses the current SCA solver plus the shared model evaluation stack."; ...
    "When M changes, TPAs are re-distributed uniformly over the serving area."];
end

function n_tpa_grid = resolve_fig6_tpa_grid(run_cfg, settings)
default_run_cfg = pinching.experiments.default_run_config();
if isequal(run_cfg.fig6.n_tpa_grid, default_run_cfg.fig6.n_tpa_grid)
    n_tpa_grid = settings.n_tpa_grid;
else
    n_tpa_grid = run_cfg.fig6.n_tpa_grid;
end
end

function figure_files = plot_fig6(results, paths, settings)
n_tpa_grid = results.n_tpa_grid;
avg_rate = results.avg_rate;
figure_files = {fullfile(paths.figure_dir, 'fig6_sca_original_comparison.png')};

fig = figure('Color', 'w', 'Position', [100, 100, 1040, 560]);
hold on;
plot(n_tpa_grid, avg_rate(1, :), '-o', 'LineWidth', 1.8, 'MarkerSize', 5, 'DisplayName', 'Pinching (SCA)');
plot(n_tpa_grid, avg_rate(2, :), '--s', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Target-oriented');
plot(n_tpa_grid, avg_rate(3, :), '--d', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Midpoint');
plot(n_tpa_grid, avg_rate(4, :), '--^', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'User-centric');
plot(n_tpa_grid, avg_rate(5, :), '--x', 'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', 'Conventional');
xlabel('Number of TPAs');
ylabel('Communication Rate [bit/s/Hz]');
title(settings.plot_title);
grid on;
if numel(n_tpa_grid) > 1
    xlim([n_tpa_grid(1), n_tpa_grid(end)]);
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
fprintf(fid, 'N: %d\n', params.N);
fprintf(fid, 'TPA grid: %s\n', mat2str(results.n_tpa_grid));
fprintf(fid, 'CVX solver used: %s\n', results.cvx_solver);
fprintf(fid, 'SCA opts: max_iters=%d, tol=%g, seed_count=%d, precision=%s\n\n', ...
    opts.max_iters, opts.tol, opts.seed_count, opts.cvx_precision);

fprintf(fid, 'Assumptions:\n');
for i = 1:numel(settings.assumptions)
    fprintf(fid, '- %s\n', settings.assumptions(i));
end
fprintf(fid, '\n');

fprintf(fid, 'Average communication rate [bit/s/Hz]\n');
fprintf(fid, 'M\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for midx = 1:numel(results.n_tpa_grid)
    fprintf(fid, '%.1f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\n', ...
        results.n_tpa_grid(midx), results.avg_rate(1, midx), results.avg_rate(2, midx), ...
        results.avg_rate(3, midx), results.avg_rate(4, midx), results.avg_rate(5, midx));
end

fprintf(fid, '\nFeasibility ratio\n');
fprintf(fid, 'M\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for midx = 1:numel(results.n_tpa_grid)
    fprintf(fid, '%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n', ...
        results.n_tpa_grid(midx), results.feasible_ratio(1, midx), results.feasible_ratio(2, midx), ...
        results.feasible_ratio(3, midx), results.feasible_ratio(4, midx), results.feasible_ratio(5, midx));
end

fprintf(fid, '\nAverage SCA iterations\n');
fprintf(fid, 'M\titerations\n');
for midx = 1:numel(results.n_tpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_tpa_grid(midx), results.avg_sca_iterations(midx));
end

fprintf(fid, '\nAverage SCA iterations among successful pinching runs\n');
fprintf(fid, 'M\titerations_success_only\n');
for midx = 1:numel(results.n_tpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_tpa_grid(midx), results.avg_sca_iterations_success_only(midx));
end

fprintf(fid, '\nSCA feasible ratio by TPA count\n');
fprintf(fid, 'M\tpinching_sca_feasible\n');
for midx = 1:numel(results.n_tpa_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.n_tpa_grid(midx), results.sca_success_ratio(midx));
end

fprintf(fid, '\nSCA status counts\n');
fprintf(fid, 'status\tcount\n');
for sidx = 1:height(results.sca_status_summary)
    fprintf(fid, '%s\t%d\n', results.sca_status_summary.status(sidx), results.sca_status_summary.count(sidx));
end
end
