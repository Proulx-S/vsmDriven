% Wrapper script to run vsmDriven analysis in batch mode
try
    % Add paths if needed
    if ~exist('doIt_vsmDriven.m', 'file')
        addpath(pwd);
    end
    
    % Run the main script
    doIt_vsmDriven;
    
    % Save completion status
    save('vsmDriven_completed.mat', 'success');
catch ME
    % Save error information
    err = struct('message', ME.message, 'stack', ME.stack);
    save('vsmDriven_error.mat', 'err');
    rethrow(ME);
end 