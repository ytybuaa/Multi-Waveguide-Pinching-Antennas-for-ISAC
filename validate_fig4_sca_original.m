function [results, run_info] = validate_fig4_sca_original(varargin)
if nargin == 1 && isstruct(varargin{1})
    run_cfg = pinching.experiments.build_run_config(varargin{1});
else
    run_cfg = pinching.experiments.build_run_config(varargin{:});
end

settings = default_fig4_settings();
params = pinching.model.default_params();
params = pinching.experiments.apply_param_overrides(params, run_cfg.param_overrides);
gamma_grid = resolve_fig4_gamma_grid(run_cfg, settings);
realizations = pinching.model.build_realizations(params);
paths = pinching.experiments.figure_output_paths(run_cfg, 4);
pinching.experiments.ensure_output_dirs(paths);
pinching.experiments.maybe_print_run_header(run_cfg, settings.run_header, params);

opts = run_cfg.sca_opts;
cvx_solver_name = pinching.experiments.configure_cvx_environment(opts);

fprintf('%s, M = %d, N = %d, Pmax = %.1f, MC = %d\n', ...
    settings.progress_label, ...
    params.M, params.N, params.Pmax, params.mc_trials);

results = pinching.experiments.run_standard_sweep( ...
    params, realizations, gamma_grid, @apply_gamma, opts, settings.context_prefix, settings.sweep_name);
results.gamma_grid = gamma_grid;
results.cvx_solver = cvx_solver_name;
results.assumptions = settings.assumptions;

fprintf('Finished Monte Carlo sweep. Rendering Fig. 4 outputs...\n');
figure_files = plot_fig4(results, paths, settings);
fprintf('Figure exported. Writing summary files...\n');
write_summary(results, params, opts, paths.summary_file, settings);

save(paths.results_file, 'results', 'params', 'realizations', 'opts');
run_info = struct( ...
    'figure_id', 4, ...
    'results_file', paths.results_file, ...
    'summary_file', paths.summary_file, ...
    'figure_files', {figure_files});
save(paths.manifest_file, 'run_info');
end

function params_run = apply_gamma(params, gamma_value)
params_run = params;
params_run.gamma_req = gamma_value;
end

function settings = default_fig4_settings()
settings = struct();
settings.run_header = 'Running Fig. 4 validation';
settings.progress_label = 'Validating Fig. 4 with the current SCA solver';
settings.context_prefix = 'Fig. 4';
settings.sweep_name = 'gamma';
settings.gamma_grid = 0:1:10;
settings.plot_title = 'Fig. 4 Validation';
settings.summary_title = 'Fig. 4 validation summary';
settings.assumptions = [ ...
    "User/target locations are sampled uniformly over the serving area."; ...
    "Infeasible realizations contribute zero communication rate."; ...
    "The pinching curve uses the current SCA solver plus the shared model evaluation stack."; ...
    "Gamma is swept over the configured grid while all other parameters follow the selected run config."];
end

function gamma_grid = resolve_fig4_gamma_grid(run_cfg, settings)
default_run_cfg = pinching.experiments.default_run_config();
if isequal(run_cfg.fig4.gamma_grid, default_run_cfg.fig4.gamma_grid)
    gamma_grid = settings.gamma_grid;
else
    gamma_grid = run_cfg.fig4.gamma_grid;
end
end

function figure_files = plot_fig4(results, paths, settings)
gamma_grid = results.gamma_grid;
avg_rate = results.avg_rate;
figure_files = {fullfile(paths.figure_dir, 'fig4_sca_original_comparison.png')};

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1040, 560]);
hold on;
plot(gamma_grid, avg_rate(1, :), '-o', 'LineWidth', 1.8, 'MarkerSize', 5, 'DisplayName', 'Pinching (SCA)');
plot(gamma_grid, avg_rate(2, :), '--s', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Target-oriented');
plot(gamma_grid, avg_rate(3, :), '--d', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'Midpoint');
plot(gamma_grid, avg_rate(4, :), '--^', 'LineWidth', 1.5, 'MarkerSize', 5, 'DisplayName', 'User-centric');
plot(gamma_grid, avg_rate(5, :), '--x', 'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', 'Conventional');
xlabel('Radar SNR Requirement');
ylabel('Communication Rate [bit/s/Hz]');
title(settings.plot_title);
grid on;
if numel(gamma_grid) > 1
    xlim([gamma_grid(1), gamma_grid(end)]);
end
legend('Location', 'northeast');
hold off;
drawnow;
print(fig, figure_files{1}, '-dpng', '-r220');
close(fig);
end

function write_summary(results, params, opts, summary_file, settings)
fid = fopen(summary_file, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '%s\n', settings.summary_title);
fprintf(fid, '%s\n\n', repmat('=', 1, strlength(settings.summary_title)));
fprintf(fid, 'MC trials: %d\n', params.mc_trials);
fprintf(fid, 'Pmax: %.2f W\n', params.Pmax);
fprintf(fid, 'Gamma grid: %s\n', mat2str(results.gamma_grid));
fprintf(fid, 'CVX solver used: %s\n', results.cvx_solver);
fprintf(fid, 'SCA opts: max_iters=%d, tol=%g, seed_count=%d, precision=%s\n\n', ...
    opts.max_iters, opts.tol, opts.seed_count, opts.cvx_precision);

fprintf(fid, 'Assumptions:\n');
for i = 1:numel(settings.assumptions)
    fprintf(fid, '- %s\n', settings.assumptions(i));
end
fprintf(fid, '\n');

fprintf(fid, 'Average communication rate [bit/s/Hz]\n');
fprintf(fid, 'gamma\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for gidx = 1:numel(results.gamma_grid)
    fprintf(fid, '%.1f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\n', ...
        results.gamma_grid(gidx), results.avg_rate(1, gidx), results.avg_rate(2, gidx), ...
        results.avg_rate(3, gidx), results.avg_rate(4, gidx), results.avg_rate(5, gidx));
end

fprintf(fid, '\nFeasibility ratio\n');
fprintf(fid, 'gamma\tpinching_sca\ttarget\tmidpoint\tuser\tconventional\n');
for gidx = 1:numel(results.gamma_grid)
    fprintf(fid, '%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n', ...
        results.gamma_grid(gidx), results.feasible_ratio(1, gidx), results.feasible_ratio(2, gidx), ...
        results.feasible_ratio(3, gidx), results.feasible_ratio(4, gidx), results.feasible_ratio(5, gidx));
end

fprintf(fid, '\nAverage SCA iterations\n');
fprintf(fid, 'gamma\titerations\n');
for gidx = 1:numel(results.gamma_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.gamma_grid(gidx), results.avg_sca_iterations(gidx));
end

fprintf(fid, '\nAverage SCA iterations among successful pinching runs\n');
fprintf(fid, 'gamma\titerations_success_only\n');
for gidx = 1:numel(results.gamma_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.gamma_grid(gidx), results.avg_sca_iterations_success_only(gidx));
end

fprintf(fid, '\nSCA feasible ratio by gamma\n');
fprintf(fid, 'gamma\tpinching_sca_feasible\n');
for gidx = 1:numel(results.gamma_grid)
    fprintf(fid, '%.1f\t%.4f\n', results.gamma_grid(gidx), results.sca_success_ratio(gidx));
end

fprintf(fid, '\nSCA status counts\n');
fprintf(fid, 'status\tcount\n');
for sidx = 1:height(results.sca_status_summary)
    fprintf(fid, '%s\t%d\n', results.sca_status_summary.status(sidx), results.sca_status_summary.count(sidx));
end
end
