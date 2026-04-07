function [results, run_info] = validate_fig2_sca_original(varargin)
if nargin == 1 && isstruct(varargin{1})
    run_cfg = pinching.experiments.build_run_config(varargin{1});
else
    run_cfg = pinching.experiments.build_run_config(varargin{:});
end

settings = default_fig2_settings();
params = default_fig2_params(settings);
params = pinching.experiments.apply_param_overrides(params, run_cfg.param_overrides);
if params.M ~= 2
    warning('pinching:Fig2FixedM', ...
        'Fig. 2 uses the two-TPA special case. Resetting M to 2 for this run.');
    params.M = 2;
    params.yT = [params.W / 3, 2 * params.W / 3];
end

cases = special_cases(params);
gamma_grid = resolve_fig2_gamma_grid(run_cfg, settings);
paths = pinching.experiments.figure_output_paths(run_cfg, 2);
pinching.experiments.ensure_output_dirs(paths);
pinching.experiments.maybe_print_run_header(run_cfg, settings.run_header, params);

n_cases = numel(cases);
n_gamma = numel(gamma_grid);

results = struct();
results.gamma_grid = gamma_grid;
results.case_names = {cases.name};
results.exhaustive_rate = zeros(n_cases, n_gamma);
results.sca_rate = zeros(n_cases, n_gamma);
results.sca_x = zeros(n_cases, n_gamma, params.M);
results.exhaustive_x = zeros(n_cases, n_gamma, params.M);
results.exhaustive_radar_snr = zeros(n_cases, n_gamma);
results.sca_radar_snr = zeros(n_cases, n_gamma);
results.sca_iterations = zeros(n_cases, n_gamma);

opts = run_cfg.sca_opts;

fprintf('Reproducing Fig. 2 with the current SCA solver, M = %d\n', params.M);

for cidx = 1:n_cases
    cfg = cases(cidx);
    fprintf('\n[%s]\n', cfg.name);

    for gidx = 1:n_gamma
        params_run = params;
        params_run.gamma_req = gamma_grid(gidx);
        fprintf('  gamma = %.1f ... ', params_run.gamma_req);

        [rate_ex, x_ex, radar_ex] = exhaustive_search(cfg, params_run);
        [sol_sca, ~] = pinching.sca.solve(cfg, params_run, opts);

        results.exhaustive_rate(cidx, gidx) = rate_ex;
        results.exhaustive_x(cidx, gidx, :) = x_ex;
        results.exhaustive_radar_snr(cidx, gidx) = radar_ex;
        results.sca_rate(cidx, gidx) = sol_sca.rate;
        results.sca_x(cidx, gidx, :) = sol_sca.x_eval;
        results.sca_radar_snr(cidx, gidx) = sol_sca.radar_snr;
        results.sca_iterations(cidx, gidx) = sol_sca.iterations;

        fprintf('done. rate(sca/ex) = %.4f / %.4f bit/s/Hz\n', sol_sca.rate, rate_ex);
    end
end

figure_files = plot_results(results, cases, paths, settings);
write_summary(results, cases, paths.summary_file, settings);
save(paths.results_file, 'results', 'cases', 'params', 'opts');

run_info = struct( ...
    'figure_id', 2, ...
    'results_file', paths.results_file, ...
    'summary_file', paths.summary_file, ...
    'figure_files', {figure_files});
save(paths.manifest_file, 'run_info');
end

function settings = default_fig2_settings()
settings = struct();
settings.run_header = 'Running Fig. 2 validation';
settings.progress_label = 'Validating Fig. 2 with the current SCA solver';
settings.gamma_grid = 0:0.5:6;
settings.grid_step = 0.5;
settings.local_steps = [4, 2, 1, 0.5, 0.25, 0.1];
settings.comparison_title = 'Fig. 2 Validation';
settings.positions_title = 'Fig. 2 TPA Positions';
settings.summary_title = 'Fig. 2 validation summary';
end

function params = default_fig2_params(settings)
params = pinching.model.default_params();
params.M = 2;
params.yT = [params.W / 3, 2 * params.W / 3];
params.grid_step = settings.grid_step;
params.local_steps = settings.local_steps;
end

function gamma_grid = resolve_fig2_gamma_grid(run_cfg, settings)
default_run_cfg = pinching.experiments.default_run_config();
if isequal(run_cfg.fig2.gamma_grid, default_run_cfg.fig2.gamma_grid)
    gamma_grid = settings.gamma_grid;
else
    gamma_grid = run_cfg.fig2.gamma_grid;
end
end

function cases = special_cases(params)
yu = 2 * params.W / 5;
yt = 3 * params.W / 5;
cases(1) = struct('name', 'Case1', 'xu', params.L / 10, 'yu', yu, 'xt', -params.L / 10, 'yt', yt);
cases(2) = struct('name', 'Case2', 'xu', params.L / 5, 'yu', yu, 'xt', -params.L / 5, 'yt', yt);
cases(3) = struct('name', 'Case3', 'xu', 3 * params.L / 10, 'yu', yu, 'xt', -3 * params.L / 10, 'yt', yt);
end

function [best_rate, best_x, best_radar_snr] = exhaustive_search(cfg, params)
x_candidates = params.x_lb:params.grid_step:params.x_ub;
best_rate = -inf;
best_x = nan(1, params.M);
best_radar_snr = 0;

for x1 = x_candidates
    for x2 = x_candidates
        x = [x1, x2];
        [rate, radar_snr, feasible, x_eval] = pinching.model.evaluate_configuration(x, cfg, params, true);
        if feasible && rate > best_rate
            best_rate = rate;
            best_x = x_eval;
            best_radar_snr = radar_snr;
        end
    end
end

if ~isfinite(best_rate)
    best_rate = 0;
end
end

function figure_files = plot_results(results, cases, paths, settings)
gamma_grid = results.gamma_grid;
figure_files = { ...
    fullfile(paths.figure_dir, 'fig2_sca_original_comparison.png'), ...
    fullfile(paths.figure_dir, 'fig2_sca_original_positions.png')};

fig1 = figure('Color', 'w', 'Position', [100, 100, 900, 520]);
hold on;
case_colors = [0.8500 0.3250 0.0980; 0 0.4470 0.7410; 0.4660 0.6740 0.1880];
for cidx = 1:numel(cases)
    plot(gamma_grid, results.sca_rate(cidx, :), '-', ...
        'Color', case_colors(cidx, :), 'LineWidth', 1.8, ...
        'DisplayName', sprintf('%s, SCA', cases(cidx).name));
    plot(gamma_grid, results.exhaustive_rate(cidx, :), 'o--', ...
        'Color', case_colors(cidx, :), 'MarkerSize', 5, 'LineWidth', 1.0, ...
        'DisplayName', sprintf('%s, Ex. Search', cases(cidx).name));
end
xlabel('Radar SNR Requirement');
ylabel('Communication Rate [bit/s/Hz]');
title(settings.comparison_title);
grid on;
legend('Location', 'eastoutside');
hold off;
exportgraphics(fig1, figure_files{1}, 'Resolution', 200);

fig2 = figure('Color', 'w', 'Position', [100, 100, 1200, 360]);
for cidx = 1:numel(cases)
    subplot(1, 3, cidx);
    hold on;
    plot(gamma_grid, squeeze(results.sca_x(cidx, :, 1)), '-o', ...
        'LineWidth', 1.5, 'MarkerSize', 4, 'DisplayName', '1st TPA');
    plot(gamma_grid, squeeze(results.sca_x(cidx, :, 2)), '-s', ...
        'LineWidth', 1.5, 'MarkerSize', 4, 'DisplayName', '2nd TPA');
    yline(cases(cidx).xu, '--', 'LineWidth', 1.2, 'DisplayName', 'User');
    yline(cases(cidx).xt, ':', 'LineWidth', 1.5, 'DisplayName', 'Target');
    xlabel('Radar SNR Requirement');
    ylabel('Horizontal Coordinate [m]');
    title(cases(cidx).name);
    grid on;
    hold off;
end
legend('Location', 'bestoutside');
exportgraphics(fig2, figure_files{2}, 'Resolution', 200);
end

function write_summary(results, cases, summary_file, settings)
fid = fopen(summary_file, 'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', settings.summary_title);
fprintf(fid, '%s\n\n', repmat('=', 1, strlength(settings.summary_title)));

for cidx = 1:numel(cases)
    fprintf(fid, '%s\n', cases(cidx).name);
    fprintf(fid, '-----\n');
    fprintf(fid, 'gamma\tsca_rate\tex_rate\tsca_x1\tsca_x2\tsca_radar\titers\n');
    for gidx = 1:numel(results.gamma_grid)
        fprintf(fid, '%.1f\t%.6f\t%.6f\t%.4f\t%.4f\t%.6f\t%d\n', ...
            results.gamma_grid(gidx), ...
            results.sca_rate(cidx, gidx), ...
            results.exhaustive_rate(cidx, gidx), ...
            results.sca_x(cidx, gidx, 1), ...
            results.sca_x(cidx, gidx, 2), ...
            results.sca_radar_snr(cidx, gidx), ...
            round(results.sca_iterations(cidx, gidx)));
    end
    avg_gap = mean(abs(results.sca_rate(cidx, :) - results.exhaustive_rate(cidx, :)));
    fprintf(fid, '\nAverage rate gap: %.6f bit/s/Hz\n\n', avg_gap);
end
end
