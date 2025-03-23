clear all
close all

%%%%%%%%%%%%
%% Set up %%
%%%%%%%%%%%%

% Detect computing environment
os   = char(java.lang.System.getProperty('os.name'));
host = char(java.net.InetAddress.getLocalHost.getHostName);
user = char(java.lang.System.getProperty('user.name'));

% Configure paths accordingly
if strcmp(os,'Linux') && strcmp(host,'takoyaki') && strcmp(user,'sebp')
    storageDir = '/local/users/sebp/';
    scratchDir = '/scratch/users/sebp/';
    toolDir    = '~/tools';
    workScript = mfilename;
    workFile   = [workScript '.mat'];
    workDir    = fullfile('~/work/vsmDriven/',workScript); if ~exist(workDir,'dir'); mkdir(workDir); end
    workFile   = fullfile(fileparts(workDir),workFile);
    envId      = 1;
else
    dbstack; error('not implemented')
end

% Load dependencies
%%% matlab
addpath(genpath(         workDir                                 ))
tool = 'vasomoTools'; toolURL = 'https://github.com/Proulx-S/vasomoTools.git';
if ~exist(fullfile(toolDir, tool), 'dir'); system(['git clone ' toolURL ' ' fullfile(toolDir, tool)]); end
addpath(genpath(fullfile(toolDir,tool)))
tool = 'chronux'; toolURL = 'https://github.com/Proulx-S/chronux';
if ~exist(fullfile(toolDir, tool), 'dir'); system(['git clone ' toolURL ' ' fullfile(toolDir, tool)]); end
addpath(genpath(fullfile(toolDir,'chronux/chronux_2_12/modified')))
tool = 'fieldtrip'; toolURL = 'https://github.com/fieldtrip/fieldtrip';
if ~exist(fullfile(toolDir, tool), 'dir'); system(['git clone ' toolURL ' ' fullfile(toolDir, tool)]); end
addpath(genpath(fullfile(toolDir,'fieldtrip/external/freesurfer')))
%%% neurodesk
switch envId
    case 1
        global src
        %%%% afni
        src.afni = 'ml afni/24.3.00';
        system([src.afni '; 3dinfo > /dev/null'],'-echo');
        %%%% freesurfer
        src.fs   = 'ml freesurfer/8.0.0';
        system([src.fs   '; mri_convert > /dev/null'],'-echo');
        %%%% fsl for fslview once we figure out how to make it work
    otherwise
        dbstack; error('not implemented')
        % neurodeskModule = {
        % ":/neurodesktop-storage/containers/freesurfer_8.0.0_20250210"
        % ":/neurodesktop-storage/containers/afni_24.3.00_20241003"};
        % for i = 1:length(neurodeskModule)
        %     if contains(getenv("PATH"),neurodeskModule{i}); continue; end
        %     setenv("PATH",getenv("PATH") + neurodeskModule{i});
        % end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load preprocessed data filenames %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
updatePreproc = 0;
if updatePreproc
    error('double-check that')
    preprocFile = '/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_generalPreproc/vsmDriven.mat';
    disp(['loading from ' preprocFile]);
    load(preprocFile,          'info','rCond','subList','runCondAcqList','runCondStimList')
    disp(['saving  to   ' mfilename('fullpath') '.mat']);
    save(mfilename('fullpath'),'info','rCond','subList','runCondAcqList','runCondStimList','-v7.3')
else
    disp(['loading from workFile ' workFile]);
    load(workFile,'info','rCond','subList','runCondAcqList','runCondStimList')
end

% Make sure paths in workFile are the correct ones
switch envId
    case 1
        rCond = renameAllPaths(rCond,{'/autofs/space/takoyaki_001/users/proulxs/' '/space/takoyaki/1/users/proulxs/'},'/local/users/sebp/martinos/');
        info  = renameAllPaths(info, {'/autofs/space/takoyaki_001/users/proulxs/' '/space/takoyaki/1/users/proulxs/'},'/local/users/sebp/martinos/');
    otherwise
        dbstack; error('not implemented')
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Anatomical processing (masks and rois) %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
do.loadIt = 0;
do.doIt   = 1;
do.saveIt = 0;
forceThis   = 0;
forceRoi    = 0;
verboseThis = 1;


% tmpField = fields(rCond{S}.vfMRI);
% fTmp = {};
% for i = 1:length(tmpField)
%     fTmp = cat(1,fTmp,rCond{S}.vfMRI.(tmpField{i}).fList);
% end
% rCond{S}.QA.vfMRI.prcSmr.sesCat.runAv.fList

for S = 1:length(rCond)
    info.sub = subList{S};
    for rca = 1:length(runCondAcqList)
        if ~strcmp(runCondAcqList{rca},'vfMRI'); continue; end
        if ~isfield(rCond{S},runCondAcqList{rca}); continue; end
        % if any(S==[6]); keyboard; end
        if isfield(rCond{S},'avMap')
            [out,avMap] = volAnatPreproc5(do,info,rCond{S}.(runCondAcqList{rca}),rCond{S}.avMap,forceThis,forceRoi);
        else
            [out,avMap] = volAnatPreproc5(do,info,rCond{S}.(runCondAcqList{rca}),rCond{S}.QA.(runCondAcqList{rca}).prcSmr,runCondAcqList{rca},[],forceThis,forceRoi);
            rCond{S}.(runCondAcqList{rca}).anat = out;
        end
        disp('----')
        disp(out.mask.vessel.f)
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Response estimation and activation detection processing
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%
%%% NOTE: Need to figure out run order. Probably need to perform a sort according to acquisition time. More importantly, run-r in the bids filename might not always match the run index here in matlab (e.g. bids run-r might not be starting at and increasing by 1, and some runs might be excluded)
%%%

if 1
    do.loadIt   = 0;
    do.doIt     = 1;
    do.saveIt   = 0;
    do.writeIt  = 1;
    forceThis   = 1;
    verboseThis = 1;

    for S = 1:size(rCond,1)
        % acqList = fields(rCond{S}); acqList(ismember(acqList,{'phs' 'QA'})) = [];
        acqList = {'vfMRI'};
        for A = 1:length(acqList)
            acq  = acqList{A}; if ~isfield(rCond{S},acq) || isempty(rCond{S}.(acq)); continue; end

            %anat
            hdMask = rCond{S}.(acq).anat.mask.head;
            veMask = rCond{S}.(acq).anat.label.vessel;

            taskList = fields(rCond{S}.(acq));
            taskList(~contains(taskList,'task_'           )) = [];
            taskList( ismember(taskList,'task_eyeOpenRest')) = [];
            taskList( ismember(taskList,'task_fixOnly'    )) = [];

            for T = 1:length(taskList)
                task = taskList{T}; if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task)); continue; end

                %ts
                volTs = cpInfoDown(...
                    rCond{S}.(acq).(task),...
                    rCond{S}.(acq).(task).volTs);
                volTs = MRIload3(volTs,[],[],1);
                for i = 1:length(volTs)
                    volTs(i).mri.nFrame     = volTs(i).nFrame;
                    volTs(i).mri.nFrameOrig = volTs(i).nFrameOrig;
                    volTs(i).tr = volTs(i).mri.tr;
                end
                % [volTs.mri.nFrame] = deal(349);
                % [volTs.nFrame] = deal(349);

                %dsgn
                dsgn = rCond{S}.(acq).(task).dsgn;

                %resp
                % info.doCat = 0;
                % info.doRun = 1;
                try

                    load /home/sebp/work/vsmDriven/doIt_vsmDriven/errorData_S-5_A-1_T-1.mat
                    rCond{S}.(acq).(task).volResp = getVolResp(info,volTs,dsgn,hdMask,forceThis,verboseThis);
                catch err
                    save(fullfile(workDir,['errorData_S-' num2str(S) '_A-' num2str(A) '_T-' num2str(T) '.mat']))
                end
                close all

            end
        end
    end
end
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

save tmp rCond
return

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Frequency-domain frequency-response prediction (fundamental only) %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
verboseThis = 2;

acq          = runCondAcqList{  contains(runCondAcqList ,{'vfMRI'})           };
taskList = runCondStimList(~contains(runCondStimList,{'task_eyeOpenRest' 'task_fixOnly'}));

% Compute
res.harm       = cell(length(rCond),length(taskList));
res.harmCanon  = cell(length(rCond),length(taskList));
res.f          = cell(length(rCond),length(taskList));
res.voxSelCond = cell(length(rCond),1                );
res.task       = cell(length(rCond),length(taskList));
for S = 1:size(rCond,1)
    
    % anatomical voxel selection
    vesselMask = MRIload3(char(rCond{S}.vfMRI.anat.label.vessel.f),[],[],0);
    % vesselMask = MRIload3(rCond{S}.label.(acq).calcarineVessel.f,[],[],0);
    vesselLabel = vesselMask.vol;
    vesselMask  = logical(vesselLabel);
    
    allLabel{S} = vesselLabel;
    allMask{S}  = vesselMask;
    
    for T = 1:length(taskList)
        task = taskList{T};
        if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task))
            continue
        end

        % load ts
        rCond{S}.(acq).(task).volTs = MRIload3(rCond{S}.(acq).(task).volTs,allMask{S},[],0);

        % perfrom mt spectral ana
        K     = 13;
        W     = [];
        win   = inf; % in seconds [lenght, step]
        extra = [];
        outField = ['volPsd_K' num2str(K) '_win' replace(num2str(win(1),'%0.1f'),'.','p')];
        
        volPsd = runFullMT5(rCond{S}.(acq).(task).volTs,W,K,win,rCond{S}.(acq).(task).dsgn,[]       ,1,0,verboseThis);
        rCond{S}.(acq).(task).volPsd = volPsd;
        % volPsd = runFullMT5(rCond{S}.(acq).(task).volTs,W,K,win,rCond{S}.(acq).(task).dsgn,allMask{S},1,0,verboseThis);

        % task
        % 1/volPsd(1).harm.f(:,:,:,:,1)
        % keyboard
        % unique(diff(rCond{S}.vfMRI.task_05sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_06sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_08sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_10sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_15sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_20sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_50sPrd1sDur.dsgn.onsetList))
        % unique(diff(rCond{S}.vfMRI.task_50sPrd5sDur.dsgn.onsetList))

        % curCond = runFullMT5(rCond{S}.(acq).(task),W,K,win,dsgn,allMask{S},extra,1    ,[]      ,verboseThis,[],[])';

        % % funPsd = runFullMT4(funTs,W,K,win,onsets,ondurs,mask     ,extra,skipSVD,skipPSD,verbose,taperPerm,phaseRand,testFlag)
        % onsets = rCond{S}.(acq).(task).dsgn.onsetList;
        % ondurs = rCond{S}.(acq).(task).dsgn.ondurList;
        % curCond = runFullMT5(rCond{S}.(acq).(task),W,K,win,onsets,ondurs,allMask{S},extra,1    ,[]      ,verboseThis,[],[])';
        % % curCond = runFullMT3(volTs,W,K,win,[],[],allMask{S},extra,[],[],verboseThis,[],[])';

        % extract line power (harmonic signal amplitudes)
        for r = 1:size(volPsd,1)
            volPsd(r).vec = permute(volPsd(r).harm.linePwr(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
            volPsd(r).f   = permute(volPsd(r).harm.f(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
            % [~,res.file{S,T}{r,1}] = fileparts(fileparts(volPsd(r).fspec));
            % [~,res.file{S,T}{r,1}] = fileparts(fileparts(volPsd(r).fspec));
        end
        res.acqTime{S,T} = rCond{S}.(acq).(task).acqTime;
        res.harm{S,T} = cat(4,volPsd.vec); % {sub x cond} [1 x vox x 1 x run]
        res.f{S,T}    = cat(4,volPsd.f); % {sub x cond} [1 x vox x 1 x run]
        res.task{S,T} = taskList{T}; % {sub x cond} [1 x vox x 1 x run]


        % % Prediction from canonical HRF
        % % load fit
        % volFit = MRIload3(rCond{S}.(acq).(task).volActCat.afni.fFit,[],[],0);
        % mri = [volTs.mri]; if length(unique([mri.nFrame]))>1; warning('XX'); end
        % volFit = cpInfoDown(...
        %     rCond{S}.(acq).(task),...
        %     volFit);
        % volFit.vol(:,:,:,volTs(1).mri.nFrame+1:end) = [];
        % volFit.nframes = volTs(1).mri.nFrame;
        % % perfrom mt spectral ana on canonical fit
        % K     = 13;
        % W     = [];
        % win   = inf; % in seconds [lenght, step]
        % extra = [];
        % outField = ['volPsd_K' num2str(K) '_win' replace(num2str(win(1),'%0.1f'),'.','p')];
        % curCond = runFullMT3(volFit,W,K,win,[],[],vesselMask&fdrMask,extra,[],[],verboseThis,[],[])';
        % % extract line power (harmonic signal amplitudes)
        % for r = 1:size(curCond,1)
        %     curCond(r).vec = permute(curCond(r).harm.linePwr(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
        %     curCond(r).f   = permutedsgn(curCond(r).harm.f(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
        % end
        % res.harmCanon{S,T} = cat(4,curCond.vec); % {sub x cond} [1 x vox x 1 x run]
        % % res.f{S,C}    = cat(4,curCond.f); % {sub x cond} [1 x vox x 1 x run]



    end
end

for S = 1:size(rCond,1)
    for T = 1:length(taskList)
        task = taskList{T};
        if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task))
            continue
        end
        res.file{S,T} = rCond{S}.(acq).(task).fOrigList;
        res.acqTime{S,T} = rCond{S}.(acq).(task).acqTime;
        res.ses{S,T}     = rCond{S}.(acq).(task).ses;
    end
end

for S = 1:size(rCond,1)
    disp(subList{S})
    rCond{S}.vfMRI.anat.label.vessel.mri = MRIload3(char(rCond{S}.vfMRI.anat.label.vessel.f),[],[],0);
    eval(['rCond_' subList{S} ' = rCond{' num2str(S) '};']);
    eval(['save(''rCond_' subList{S} ''',''rCond_' subList{S} ' '',''-v7.3'');']);
    eval(['clear rCond_' subList{S} ';']);
end
clear rCond
save('timeSeriesData')
return

%% Plot

% Remove bad runs
S = 5;
T = ismember(taskList,'task_10sPrd50dc');
R = [2 3];
res.harm{S,T}(:,:,:,R) = [];
res.f{S,T}(:,:,:,R) = [];
res.file{S,T}(R) = [];
res.acqTime{S,T}(R) = [];
res.ses{S,T}(R) = [];
T = ismember(taskList,'task_15sPrd50dc');
R = 2;
res.harm{S,T}(:,:,:,R) = [];
res.f{S,T}(:,:,:,R) = [];
res.file{S,T}(R) = [];
res.acqTime{S,T}(R) = [];
res.ses{S,T}(R) = [];
T = ismember(taskList,'task_30sPrd50dc');
R = 1:3;
res.harm{S,T}(:,:,:,R) = [];
res.f{S,T}(:,:,:,R) = [];
res.file{S,T}(R) = [];
res.acqTime{S,T}(R) = [];
res.ses{S,T}(R) = [];



% Summarize
harm        = cell(length(rCond),length(taskList));
harmAv      = cell(length(rCond),length(taskList));
harmEr      = cell(length(rCond),length(taskList));
harmCanon   = cell(length(rCond),length(taskList));
harmCanonAv = cell(length(rCond),length(taskList));
harmNrun    = cell(length(rCond),length(taskList));
harmNvox    = cell(length(rCond),length(taskList));
harmF       = cell(length(rCond),length(taskList));
harmTask    = cell(length(rCond),length(taskList));
for S = 1:size(res.harm,1)
    for T = 1:size(res.harm,2)
        if ~isempty(res.harm{S,T})
            % average across voxels
            harm{S,T}      = mean(abs(res.harm{S,T}),2); % {sub x cond} [1 x 1 x 1 x run]
            % summarize across runs
            harmAv{S,T}    = mean(harm{S,T},4)    ; % {sub x cond} [1 x 1 x 1 x 1]
            harmEr{S,T}    = std(harm{S,T},[],4)  ; % {sub x cond} [1 x 1 x 1 x 1]
            harmNrun{S,T}  = size(harm{S,T},4)    ; % {sub x cond} [1 x 1 x 1 x 1]
            harmNvox{S,T}  = size(res.harm{S,T},2); % {sub x cond} [1 x 1 x 1 x 1]
            harmF{S,T}     = unique(res.f{S,T})   ; % {sub x cond}
            harmTask{S,T}  = res.task{S,T}        ; % {sub x cond}
            % % similar for canonical prediction
            % harmCanon{S,T}   = mean(abs(res.harmCanon{S,T}),2); % {sub x cond} [1 x 1 x 1 x run]
            % harmCanonAv{S,T} = mean(harmCanon{S,T},4)    ; % {sub x cond} [1 x 1 x 1 x 1]
        else
            harm{S,T}     = nan;
            harmAv{S,T}   = nan;
            harmEr{S,T}   = nan;
            harmNrun{S,T} = nan;
            harmNvox{S,T} = nan;
            harmF{S,T}    = nan;
            harmCanon{S,T}   = nan;
            harmCanonAv{S,T} = nan;
            harmTask{S,T}  = '';
        end
    end
end
harmAv   = flip(cell2mat(harmAv)  ,2);
harmEr   = flip(cell2mat(harmEr)  ,2);
harmNrun = flip(cell2mat(harmNrun),2);
harmNvox = flip(cell2mat(harmNvox),2);
harmF    = flip(cell2mat(harmF)   ,2);
harmTask = flip(         harmTask ,2);
for i = 1:size(harmTask,2); harmTask(:,i) = unique(harmTask(~cellfun('isempty',harmTask(:,i)),i)); end; harmTask(2:end,:) = [];
table(harmF(:,1),harmF(:,2),harmF(:,3),harmF(:,4),harmF(:,5),harmF(:,6),harmF(:,7),harmF(:,8),harmF(:,9),harmF(:,10),harmF(:,11),harmF(:,12),'VariableNames',harmTask)
% harmCanonAv = flip(cell2mat(harmCanonAv),2);

fFreq = figure('WindowStyle','docked');
ind50dc = contains(harmTask,'50dc');
ind1s = contains(harmTask,'1sDur');
harmTask(ind1s)'
harmTask(ind50dc)'
for S = 1:size(harmAv,1)
    ind     = ~isnan(harmF(S,:)) & ~ind50dc & ind1s;
    hErr(S) = errorbar(harmF(S,ind),harmAv(S,ind),harmEr(S,ind)./sqrt(harmNrun(S,ind))); hold on
    % text(f(S,ind),harmAv(S,ind),num2str(harmNvox(S,ind)'))
end
set(hErr,'CapSize',0,'Marker','o','MarkerFaceColor','w')
grid on
xlabel('Stimulus frequency (Hz)')
ylabel({'response at stimulus frequency' 'harmonic signal amplitude' '+/-SEM across runs or subjects'})
xLim = xlim; xLim(1) = 0; xlim(xLim)



% pool some frequencies for group average
fOk = nan(1,size(harmF,2)); for metInd = 1:size(harmF,2); tmp = harmF(~isnan(harmF(:,metInd)),metInd); if ~isempty(tmp); fOk(metInd) = unique(tmp); end; end
harmAvTmp = harmAv(:,~ind50dc & ind1s);
fOk     = fOk(~ind50dc & ind1s);
harmAvSmr = [];
fSmr    = [];
b = fOk<0.05;
harmAvSmr(:,end+1) = mean(harmAvTmp(:,b),2,'omitmissing');
fSmr(1,end+1)    = mean(fOk(b));
[~,b] = min(abs(fOk-0.0661));
harmAvSmr(:,end+1) = mean(harmAvTmp(:,b),2,'omitmissing')
fSmr(1,end+1)    = mean(fOk(b));
[~,b] = min(abs(fOk-0.0992));
harmAvSmr(:,end+1) = mean(harmAvTmp(:,b),2,'omitmissing')
fSmr(1,end+1)    = mean(fOk(b));
hErGr = errorbar(fSmr,mean(harmAvSmr,1),std(harmAvSmr,[],1)./sqrt(size(harmAvSmr,1)));
set(hErGr,'CapSize',0,'Marker','o','MarkerFaceColor','k','Color','k','MarkerEdgeColor','k','MarkerSize',10,'LineWidth',2)


% add 50dc
fOk = nan(1,size(harmF,2)); for metInd = 1:size(harmF,2); tmp = harmF(~isnan(harmF(:,metInd)),metInd); if ~isempty(tmp); fOk(metInd) = unique(tmp); end; end
fSmr        = fOk(ind50dc);
harmAvSmr   = harmAv(:,ind50dc);
harmErSmr   = harmEr(:,ind50dc);
harmNrunSmr = harmNrun(:,ind50dc);
ind         = false(size(harmAvSmr,1),1);
for S = 1:size(harmAvSmr,1)
    if any(isnan(harmAvSmr(S,:))); continue; end
    ind(S) = true;
    hErrDC(S) = errorbar(fSmr,harmAvSmr(S,:),harmErSmr(S,:)./sqrt(harmNrunSmr(S,:)));
    set(hErrDC(S),'Color',hErr(S).Color,'LineStyle','--','CapSize',0,'Marker','^','MarkerFaceColor','w')
end
legend([hErr hErGr hErrDC(ind)],[subList; {'groupe mean'}; strcat(subList(ind),' 50%dc')],'box','off','AutoUpdate','off')
ylim([2 19])





%% Plot add neural drive prediction
% get all designs
taskList2 = taskList(contains(taskList,'1sDur'));
clear dsgn
for T = 1:length(taskList2)
    task = taskList2{T};
    for S = 1:size(rCond,1)
        if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task))
            continue
        else
            dsgn(T,1) = rCond{S}.(acq).(task).dsgn;
        end
    end
end
dsgn(:,2) = dsgn(:,1);
for T = 1:size(dsgn,1)
    dsgn(T,2).ondurList = repmat(mean(diff(dsgn(T,1).onsetList))/2,size(dsgn(T,1).onsetList));
end

% generate stimulus drive timeseries
rCondStim = runCond;
rCondStim.nFrame     = rCond{1}.vfMRI.task_05sPrd1sDur.nFrame(1);
rCondStim.nFrameOrig = rCond{1}.vfMRI.task_05sPrd1sDur.nFrameOrig(1);
rCondStim.volTs      = rCond{1}.vfMRI.task_05sPrd1sDur.volTs(1);
rCondStim.volTs.mri.fspec = [];
rCondStim = repmat(rCondStim,size(dsgn));
for i = 1:numel(rCondStim)
    rCondStim(i).dsgn = dsgn(i);
    tr = rCondStim(i).volTs.mri.tr/1000;
    t  = linspace(0,(rCondStim(i).nFrameOrig-1)*tr,rCondStim(i).nFrameOrig);
    t  = t(rCondStim(i).nFrameOrig-rCondStim(i).nFrame+1:end);
    ts = zeros(size(t));
    for e = 1:length(rCondStim(i).dsgn.onsetList)
        ts(...
        t >= rCondStim(i).dsgn.onsetList(e) & ...
        t <= rCondStim(i).dsgn.onsetList(e) + rCondStim(i).dsgn.ondurList(e) - tr/2 ...
        ) = 1;
    end
    rCondStim(i).volTs.mri.vol = permute(ts,[1 3 4 2]);
    rCondStim(i).volTs.mri.t = t';
    rCondStim(i).volTs.mri = vol2vec(rCondStim(i).volTs.mri);
end




% % % % % %%%%%%%%%%%%%%%%%%%
% % % % % %%%%%%%%%%%%%%%%%%%
% % % % % % David's request %
% % % % % rCondStim = runCond;
% % % % % rCondStim.nFrame     = rCond{1}.vfMRI.task_05sPrd1sDur.nFrame(1);
% % % % % rCondStim.nFrameOrig = rCond{1}.vfMRI.task_05sPrd1sDur.nFrameOrig(1);
% % % % % rCondStim.volTs      = rCond{1}.vfMRI.task_05sPrd1sDur.volTs(1);
% % % % % rCondStim.volTs.mri.fspec = [];
% % % % % rCondStim = repmat(rCondStim,size(dsgn));
% % % % % 
% % % % % s0 = dsgn(1,2).onsetList(1);
% % % % % dsgnLow = dsgn(1,2);
% % % % % freq = 0:0.01:0.1; freq(1) = [];
% % % % % % dsgnLow.onsetList = 
% % % % % 
% % % % % for i = 1:numel(rCondStim)
% % % % %     rCondStim(i).dsgn = dsgn(i);
% % % % %     tr = rCondStim(i).volTs.mri.tr/1000;
% % % % %     t  = linspace(0,(rCondStim(i).nFrameOrig-1)*tr,rCondStim(i).nFrameOrig);
% % % % %     t  = t(rCondStim(i).nFrameOrig-rCondStim(i).nFrame+1:end);
% % % % %     ts = zeros(size(t));
% % % % %     for e = 1:length(rCondStim(i).dsgn.onsetList)
% % % % %         ts(...
% % % % %         t >= rCondStim(i).dsgn.onsetList(e) & ...
% % % % %         t <= rCondStim(i).dsgn.onsetList(e) + rCondStim(i).dsgn.ondurList(e) - tr/2 ...
% % % % %         ) = 1;
% % % % %     end
% % % % %     rCondStim(i).volTs.mri.vol = permute(ts,[1 3 4 2]);
% % % % %     rCondStim(i).volTs.mri.t = t';
% % % % %     rCondStim(i).volTs.mri = vol2vec(rCondStim(i).volTs.mri);
% % % % % end
% % % % % 
% % % % % s = rCondStim(i).volTs.mri.vec;
% % % % % t = rCondStim(i).volTs.mri.t - rCondStim(i).volTs.mri.t(1);
% % % % % h = spmhrf(t);
% % % % % 
% % % % % plot(abs(fft(h).*fft(s)))
% % % % % 
% % % % % 
% % % % % 
% % % % % plot(t,h)
% % % % % c = conv(s,h,'same');
% % % % % hold on
% % % % % plot(t,s)
% % % % % plot(t,c)
% % % % % % David's request %
% % % % % %%%%%%%%%%%%%%%%%%%
% % % % % %%%%%%%%%%%%%%%%%%%







close all
ax = {};
for T = 1:size(rCondStim,1)
    figure('WindowStyle','docked');
    ax{end+1} = gca;
    stairs(rCondStim(T,1).volTs.mri.t,rCondStim(T,1).volTs.mri.vec);
    hold on
    stairs(rCondStim(T,2).volTs.mri.t,rCondStim(T,2).volTs.mri.vec*1.1);
    ylim([-0.1 1.2])
end

for i = 1:numel(rCondStim)
    % perfrom mt spectral ana
    K     = 13;
    W     = [];
    win   = inf; % in seconds [lenght, step]
    extra = [];
    % outField = ['volPsd_K' num2str(K) '_win' replace(num2str(win(1),'%0.1f'),'.','p')];

    rCondStim(i).volPsd = runFullMT5(rCondStim(i).volTs,W,K,win,rCondStim(i).dsgn,[],1,0,verboseThis);
end

linePwr = nan(size(rCondStim));
freq = nan(size(rCondStim));
dc = nan(size(rCondStim));
for i = 1:numel(rCondStim)
    linePwr(i) = rCondStim(i).volPsd.harm.linePwr(1,1,1,1,1);
    freq(i) = 1/mean(diff(rCondStim(i).dsgn.onsetList));
    dc(i) = mean(rCondStim(i).dsgn.ondurList)/mean(diff(rCondStim(i).dsgn.onsetList));
end
uiopen('/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven/summaryCleanP5.fig',1)
hold on
plot(freq(:,1),abs(linePwr(:,1))*150)
plot(freq(:,2),abs(linePwr(:,2))*35)



return






% 
% %%% Group summary
% harmAvNorm = harmAv - mean(harmAv,2,'omitmissing') + mean(mean(harmAv,2,'omitmissing'));
% harmAvNormAv = mean(harmAvNorm(:,~ind50dc & ind1s),1,'omitmissing');
% harmAvNormEr = std(harmAvNorm,[],1,'omitmissing');
% harmAvNormN  = sum(~isnan(harmAvNorm));
% 
% % pool low frequencies
% fOk = nan(1,size(harmF,2)); for metInd = 1:size(harmF,2); tmp = harmF(~isnan(harmF(:,metInd)),metInd); if ~isempty(tmp); fOk(metInd) = unique(tmp); end; end
% harmAvNormLowFreq = harmAvNorm(:,fOk<0.05);
% harmAvNormLowFreqN  = sum(~isnan(harmAvNormLowFreq(:)));
% fAvNorm      = [mean(fOk(fOk<0.05))                          fOk(fOk>0.05)           ];
% harmAvNormAv = [mean(harmAvNormLowFreq(:),1,'omitmissing')   harmAvNormAv(:,fOk>0.05)];
% harmAvNormEr = [std(harmAvNormLowFreq(:),[],1,'omitmissing') harmAvNormEr(:,fOk>0.05)];
% harmAvNormN  = [sum(~isnan(harmAvNormLowFreq(:)))            harmAvNormN(:,fOk>0.05) ];
% 
% % add to plot
% hErGr = errorbar(fAvNorm(harmAvNormN>1),harmAvNormAv(harmAvNormN>1),harmAvNormEr(harmAvNormN>1)./sqrt(harmAvNormN(harmAvNormN>1)));
% set(hErGr,'CapSize',0,'Marker','^','MarkerFaceColor','k','Color','k','MarkerEdgeColor','k','MarkerSize',10,'LineWidth',2)


%%% Canonical prediction
S = 1
% ind = ~isnan(f(S,:));
% hPred = plot(f(S,ind),harmCanonAv(S,ind),':*','Color',hErr(S).Color); hold on
% legend([hErr hErGr hPred],[subList; {'groupe mean'}; {'canonHRF'}],'box','off','AutoUpdate','off')

%%% Canonical prediction (equal stimulus model amplitude)
% !!!variable duty cycle (1% to 50%)!!!
S = 1;
% get average coef from task_50sPrd5sDur
T = ismember(taskList,'task_50sPrd5sDur');
task = taskList{T};
coef = MRIread(rCond{S}.(acq).(task).volActCat.fs.fCoef); coef = coef.vol;
coef = permute(coef,[4 1 2 3]);
coef = coef(:,allMask{S});
slp = coef(1,:)'\coef(2,:)';
slpPos = coef(1,coef(1,:)>0)'\coef(2,coef(1,:)>0)';
slpNeg = coef(1,coef(1,:)<0)'\coef(2,coef(1,:)<0)';
coefMod = [1 slp];
% figure('WindowStyle','docked');
% scatter(coef(1,:),coef(2,:),'MarkerEdgeColor','k'); hold on
% grid on
% hRef = refline(slp,0); hRef.Color = 'k';
% xLim = xlim;
% yLim = ylim;
% xx = [0 xLim(2)]; yy = xx.*slpPos;
% line(xx,yy,'color','r')
% xx = [xLim(1) 0]; yy = xx.*slpNeg;
% line(xx,yy,'color','b')

cMap = flip(turbo(size(res.f,2)),1);
figure('WindowStyle','docked');
fitTs = cell(1,length(taskList));
hP    = cell(1,length(taskList));
fX    = nan(1,length(taskList));
for T = 1:length(taskList)
    task = taskList{T};
    if ~isfield(rCond{S}.(acq),task)
            % || strcmp(runCondStim,'task_50sPrd5sDur')
        continue
    end
    fFig = open(rCond{S}.(acq).(task).volActCat.afni.fMatFig);
    xMat = fFig.Children.Children.CData;
    close(fFig)
    rgr = xMat(logical(xMat(:,1)),end-1:end);
    fX(T)   = 1./mean(diff(rCond{S}.(acq).(task).dsgn.onsetList));
    fX(T)   = 1./mean(diff(rCond{S}.(acq).(task).dsgn.onsetList));
    fitTs{T}         = cpInfoDown(rCond{S}.(acq).(task),rCond{S}.(acq).(task).volTs(1));
    fitTs{T}.mri.vol = permute(rgr*coefMod',[2 3 4 1]);
    t = linspace(0,(fitTs{T}.mri.nFrame-1)*fitTs{T}.mri.tr/1000,fitTs{T}.mri.nFrame) + fitTs{T}.mri.nDummyRemoved*fitTs{T}.mri.tr/1000;
    hP{T} = plot(t,squeeze(fitTs{T}.mri.vol),'Color',cMap(T,:)); hold on

    K     = 13;
    W     = [];
    win   = inf; % in seconds [lenght, step]
    extra = [];
    outField = ['volPsd_K' num2str(K) '_win' replace(num2str(win(1),'%0.1f'),'.','p')];
    curCond = runFullMT3(fitTs{T},W,K,win,[],[],[],extra,[],[],verboseThis,[],[])';
    % extract line power (harmonic signal amplitudes)
    for r = 1:size(curCond,1)
        curCond(r).vec = permute(curCond(r).harm.linePwr(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
        curCond(r).f   = permute(curCond(r).harm.f(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
    end
    res.harmCanon2{S,T} = cat(4,curCond.vec); % {sub x cond} [1 x vox x 1 x run]
end
set([hP{ismember(taskList,{'task_05sPrd1sDur' 'task_10sPrd1sDur' 'task_50sPrd1sDur'})}],'LineWidth',3)
ind = isnan(fX);
fitTs(ind) = [];
fX(ind) = [];
hP(ind) = [];
legend([hP{:}],taskList(~ind),'interpreter','none')
xlim([54 150])

figure(fFreq)
ind = ~cellfun('isempty',res.f(S,:));

fX = [];
harmCanon2 = [];
for T = 1:length(taskList)
    if isempty(res.f{S,T}); continue; end
    fX         = [fX         res.f{S,T}(:,:,:,1)];
    harmCanon2 = [harmCanon2 res.harmCanon2{S,T}];
end
hPred2 = plot(fX,abs(harmCanon2)*35,'*:k')



%%% Canonical prediction (equal stimulus model amplitude)
% !!!fixed duty cycle (50%)!!!
S = 1;
% get average coef from task_50sPrd5sDur
T = ismember(taskList,'task_50sPrd5sDur');
task = taskList{T};
coef = MRIread(rCond{S}.(acq).(task).volActCat.fs.fCoef); coef = coef.vol;
coef = permute(coef,[4 1 2 3]);
coef = coef(:,allMask{S});
slp = coef(1,:)'\coef(2,:)';
slpPos = coef(1,coef(1,:)>0)'\coef(2,coef(1,:)>0)';
slpNeg = coef(1,coef(1,:)<0)'\coef(2,coef(1,:)<0)';
coefMod = [1 slp];
% figure('WindowStyle','docked');
% scatter(coef(1,:),coef(2,:),'MarkerEdgeColor','k'); hold on
% grid on
% hRef = refline(slp,0); hRef.Color = 'k';
% xLim = xlim;
% yLim = ylim;
% xx = [0 xLim(2)]; yy = xx.*slpPos;
% line(xx,yy,'color','r')
% xx = [xLim(1) 0]; yy = xx.*slpNeg;
% line(xx,yy,'color','b')

figure('WindowStyle','docked');
fitTs = cell(1,length(taskList));
hP    = cell(1,length(taskList));
fX    = nan(1,length(taskList));
for T = 1:length(taskList)
    task = taskList{T};
    if ~isfield(rCond{S}.(acq),task)
            % || strcmp(runCondStim,'task_50sPrd5sDur')
        continue
    end
    
    fFig = open(xMatAlt{T});
    xMat = fFig.Children.Children.CData;
    close(fFig)
    rgr = xMat(logical(xMat(:,1)),end-1:end);
    fX(T)   = 1./mean(diff(rCond{S}.(acq).(task).dsgn.onsetList));
    fX(T)   = 1./mean(diff(rCond{S}.(acq).(task).dsgn.onsetList));
    fitTs{T}         = cpInfoDown(rCond{S}.(acq).(task),rCond{S}.(acq).(task).volTs(1));
    fitTs{T}.mri.vol = permute(rgr*coefMod',[2 3 4 1]);
    t = linspace(0,(fitTs{T}.mri.nFrame-1)*fitTs{T}.mri.tr/1000,fitTs{T}.mri.nFrame) + fitTs{T}.mri.nDummyRemoved*fitTs{T}.mri.tr/1000;
    hP{T} = plot(t,squeeze(fitTs{T}.mri.vol),'Color',cMap(T,:)); hold on

    K     = 13;
    W     = [];
    win   = inf; % in seconds [lenght, step]
    extra = [];
    outField = ['volPsd_K' num2str(K) '_win' replace(num2str(win(1),'%0.1f'),'.','p')];
    curCond = runFullMT3(fitTs{T},W,K,win,[],[],[],extra,[],[],verboseThis,[],[])';
    % extract line power (harmonic signal amplitudes)
    for r = 1:size(curCond,1)
        curCond(r).vec = permute(curCond(r).harm.linePwr(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
        curCond(r).f   = permute(curCond(r).harm.f(:,:,:,:,1,:,:),[1 6 2 3 4 5 7]);
    end
    res.harmCanon3{S,T} = cat(4,curCond.vec); % {sub x cond} [1 x vox x 1 x run]
end
set([hP{ismember(taskList,{'task_05sPrd1sDur' 'task_10sPrd1sDur' 'task_50sPrd1sDur'})}],'LineWidth',3)
ind = isnan(fX);
fitTs(ind) = [];
fX(ind) = [];
hP(ind) = [];
legend([hP{:}],taskList(~ind),'interpreter','none','box','off')
xlim([54 150])

figure(fFreq)
ind = ~cellfun('isempty',res.f(S,:));

fX = [];
harmCanon3 = [];
for T = 1:length(taskList)
    if isempty(res.f{S,T}); continue; end
    fX         = [fX         res.f{S,T}(:,:,:,1)];
    harmCanon3 = [harmCanon3 res.harmCanon3{S,T}];
end
hPred3 = plot(fX,abs(harmCanon3)*35,'sq-.k')
legend([hErr hErGr hPred2 hPred3],[subList; {'groupe mean'}; {'1sDur canonHRF prediction'}; {'50%dutyCycle canonHRF prediction'}],'box','off','AutoUpdate','off')

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
return



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Time-domain frequency-response prediction %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
verboseThis = 2;

acq          = runCondAcqList{  contains(runCondAcqList ,{'vfMRI'})           };
taskList = runCondStimList(~contains(runCondStimList,{'task_eyeOpenRest'}));

% Compute
res.task           = cell(length(rCond),length(taskList));
res.respPosArt     = cell(length(rCond),length(taskList));
res.respNegArt     = cell(length(rCond),length(taskList));
res.respPosVei     = cell(length(rCond),length(taskList));
res.respNegVei     = cell(length(rCond),length(taskList));
res.respPosArtSz = cell(length(rCond),length(taskList));
res.respNegArtSz = cell(length(rCond),length(taskList));
res.respPosVeiSz = cell(length(rCond),length(taskList));
res.respNegVeiSz = cell(length(rCond),length(taskList));
res.t              = cell(length(rCond),length(taskList));
res.f              = cell(length(rCond),length(taskList));
res.voxSelCond     = cell(length(rCond),1                          );
for S = 1:size(rCond,1)
    
    % Anatomical voxel selection / classification as vein or artery
    volLabel = MRIload3(rCond{S}.label.(acq).calcarineVessel.f,[],[],0);
    % artery -> 902
    % vein   -> 914
    % unkown -> 30 or 62
    vesMask = volLabel.vol~=0  ; % vessels (including ambiguous aartery vs vein identities)
    artMask = volLabel.vol==902; % arteries
    veiMask = volLabel.vol==914; % veins
    
    % Functional (SPM canon+deriv) voxel selection / classification 
    %%% selection condition 
    if isfield(rCond{S}.(acq),'task_50sPrd5sDur') && ~isempty(rCond{S}.(acq).task_50sPrd5sDur)
        curCond = rCond{S}.(acq).task_50sPrd5sDur;
    elseif isfield(rCond{S}.(acq),'task_50sPrd1sDur') && ~isempty(rCond{S}.(acq).task_50sPrd1sDur)
        % special case (vsmDrivenP3):
        % we don't have task_50sPrd5sDur for this subject, so
        % let's use task_50sPrd1sDur. Importantly, we must discard
        % task_50sPrd1sDur from the final analysis.
        curCond = rCond{S}.(acq).task_50sPrd1sDur;
        % or we just don't use any functional mask, allowing to keep the
        % task_50sPrd1sDur condition for the final analysis
        % % % % % % % % % curCond = [];
    else
        error('can''t find a condition for voxel selection' )
    end
    res.voxSelCond{S} = ['task_' curCond.label];

    pVal            = MRIread(curCond.volActCat.fs.fFullP); pVal = pVal.vol;
    fdrVal          = nan(size(pVal));
    fdrVal(vesMask) = mafdr(pVal(vesMask));
    
    amp = MRIread(curCond.volActCat.fs.fCoefPol); amp = amp.vol;
    % positively activated voxels 
    posMask = abs(amp(:,:,:,2))<pi/2; % & fdrVal<0.05;
    % negatively activated voxels
    negMask = abs(amp(:,:,:,2))>pi/2; % & fdrVal<0.05;
        


    % Extract response timecourses
    for T = 1:length(taskList)
        task = taskList{T};
        if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task)) ...
                || strcmp(task,res.voxSelCond{S}) ...
                || strcmp(task,'task_50sPrd5sDur')
            % skip if condition does not exist
            % or if it was used for voxel selection/classification
            % or if it is the 5sDur condition
            continue
        end
        
        % load response ts
        curCond = rCond{S}.(acq).(task);
        mri = MRIread(curCond.volRespCat.fs.fRespTs);
        im = permute(mri.vol,[4 1 2 3]);
        res.task{S,T}       = curCond.label;
        res.respPosArt{S,T} = mean(im(:,posMask & artMask                        ),2);
        res.respNegArt{S,T} = mean(im(:,negMask & artMask                        ),2);
        res.respPosVei{S,T} = mean(im(:,posMask & veiMask                        ),2);
        res.respNegVei{S,T} = mean(im(:,negMask & veiMask                        ),2);
        res.respPosAmb{S,T} = mean(im(:,posMask & (vesMask & ~artMask & ~veiMask)),2);
        res.respNegAmb{S,T} = mean(im(:,negMask & (vesMask & ~artMask & ~veiMask)),2);

        
        res.respPosArtSz{S,T} = [size(im(:,posMask & artMask                        )) size(curCond.volTs,1)]; % T x Nvox x Nruns
        res.respNegArtSz{S,T} = [size(im(:,negMask & artMask                        )) size(curCond.volTs,1)];
        res.respPosVeiSz{S,T} = [size(im(:,posMask & veiMask                        )) size(curCond.volTs,1)];
        res.respNegVeiSz{S,T} = [size(im(:,negMask & veiMask                        )) size(curCond.volTs,1)];
        res.respPosAmb{S,T}   = [size(im(:,posMask & (vesMask & ~artMask & ~veiMask))) size(curCond.volTs,1)];
        res.respNegAmb{S,T}   = [size(im(:,negMask & (vesMask & ~artMask & ~veiMask))) size(curCond.volTs,1)];
        
        tr = mri.tr/1000;
        n  = mri.nframes;
        res.t{S,T} = linspace(0,tr*(n-1),n)';
        res.f{S,T} = 1/mean(diff(curCond.dsgn.onsetList)); % {sub x cond} [time x vox x 1 x run]
    end
end

for i = 1:numel(res.f)
    if isempty(res.f{i})
        res.f{i} = nan;
    end
end
res.f = cell2mat(res.f);

% Plot all
cMap = flip(turbo(size(res.f,2)),1);
voxClassList = {'PosArt' 'NegArt' 'PosVei' 'NegVei'};
fFig1  = cell(size(res.f,1));
ht1 = cell(size(res.f,1));
ax1 = cell(size(res.f,1),length(voxClassList));
f2  = cell(size(res.f,1));
ht2 = cell(size(res.f,1));
ax2 = cell(size(res.f,1),length(voxClassList));
for S = 1:size(res.f,1)
    fFig1{S} = figure('WindowStyle','docked');
    ht1{S} = tiledlayout(2,2); ht1{S,T}.Padding = 'tight'; ht1{S,T}.TileSpacing = 'tight';
    f2{S} = figure('WindowStyle','docked');
    ht2{S} = tiledlayout(2,2); ht2{S,T}.Padding = 'tight'; ht2{S,T}.TileSpacing = 'tight';
    for V = 1:length(voxClassList)
        voxClass = voxClassList{V};
        if all(cellfun('isempty',res.(['resp' voxClass])(S,:))) || all(isnan(cat(1,res.(['resp' voxClass]){S,:})))
            nexttile(ht1{S});
            nexttile(ht2{S});
            continue
        else
            ax1{S,V} = nexttile(ht1{S}); hold(ax1{S,V},'on');
            ax2{S,V} = nexttile(ht2{S}); hold(ax2{S,V},'on');
        end
        Cok = false(1,size(res.f,2));
        t = [];
        y = [];
        f = [];
        for T = 1:size(res.f,2)
            if ~isempty(res.(['resp' voxClass]){S,T}) && any(~isnan(res.(['resp' voxClass]){S,T}))
                plot(ax1{S,V},...
                    res.t{S,T},...
                    res.(['resp' voxClass]){S,T},...
                    'color',cMap(T,:));
                plot3(ax2{S,V},...
                    res.t{S,T},...
                    repmat(res.f(S,T),size(res.t{S,T})),...
                    res.(['resp' voxClass]){S,T},...
                    'color',cMap(T,:)); hold on
                Cok(1,T) = true;
                % t = [t; res.t{S,C}];
                % y = [y; res.(['resp' voxClass]){S,C}];
                % f = [f; repmat(res.f(S,C),size(res.(['resp' voxClass]){S,C}))];
            end
        end
        grid(ax1{S,V},'on')
        grid(ax2{S,V},'on')
        axis(ax1{S,V},'tight')
        axis(ax2{S,V},'tight')
        sz = cell2mat(res.(['resp' voxClass 'Sz'])(S,:)');
        if V==2
            legend(ax1{S,V},...
                strcat(res.task(S,Cok)','; nRun=', cellstr(num2str(sz(:,3)))),...
                'AutoUpdate','off','Box','off');
            legend(ax2{S,V},...
                strcat(res.task(S,Cok)','; nRun=', cellstr(num2str(sz(:,3)))),...
                'AutoUpdate','off','Box','off');
        end
        title(ax1{S,V},[subList{S} '; nVox=' num2str(sz(1,2)) '; ' voxClass])
        title(ax2{S,V},[subList{S} '; nVox=' num2str(sz(1,2)) '; ' voxClass])
        uistack(yline(ax1{S,V},0),'bottom');


        % plot3
        % [T,F] = meshgrid(linspace(min(t),max(t),10),linspace(min(f),max(f),10))
        % Y = interp2(t,f,y,T(:),F(:));
        % surf(t,f,y)
        
        xlabel(ax2{S,V},'time (s)')
        ylabel(ax2{S,V},'stim freq (Hz)')
        zlabel(ax2{S,V},'MR signal change (a.u.)')
    end
    set([ax2{S,:}],'view',[-15 20]);

    yLim1{S} = get([ax1{S,:}],'ylim'); yLim1{S} = [-1 1].*max(abs([yLim1{S}{:}])); set([ax1{S,:}],'ylim',yLim1{S});
    zLim2{S} = get([ax2{S,:}],'zlim'); zLim2{S} = [-1 1].*max(abs([zLim2{S}{:}])); set([ax2{S,:}],'zlim',zLim2{S});
end
drawnow
xLim1 = get([ax1{:}],'xlim'); xLim1 = [min([xLim1{:}]) max([xLim1{:}])]; set([ax1{:}],'xlim',xLim1);
xLim2 = get([ax2{:}],'xlim'); xLim2 = [min([xLim2{:}]) max([xLim2{:}])]; set([ax2{:}],'xlim',xLim2);
yLim2 = get([ax2{:}],'ylim'); yLim2 = [min([yLim2{:}]) max([yLim2{:}])]; set([ax2{:}],'ylim',yLim2);



% Group summary
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    % number of tPts
    if iscell(res.(['resp' voxClass 'Sz'])) % -> S x C x [Nt Nvox Nrun]
        res.(['resp' voxClass 'Sz'])(cellfun('isempty',res.(['resp' voxClass 'Sz']))) = {[nan nan nan]};
        res.(['resp' voxClass 'Sz']) = permute(cell2mat(permute(res.(['resp' voxClass 'Sz']),[1 3 2])),[1 3 2]);
    end
    for T = 1:size(res.f,2)
        ind = ~isnan(res.(['resp' voxClass 'Sz'])(:,T,1));
        if any(ind)
            res.(['resp' voxClass 'Sz'])(:,T,1) = unique(res.(['resp' voxClass 'Sz'])(ind,T,1))
        end
    end
    % number of runs
    for S = 1:size(res.f,1)
        for T = 1:size(res.f,2)
            if isnan(res.f(S,T))
                res.(['resp' voxClass 'Sz'])(S,T,3) = 0;
            end
        end
    end
    % number of voxels
    tmp = res.(['resp' voxClass 'Sz'])(:,:,2);
    ind = isnan(res.(['resp' voxClass 'Sz'])(:,:,2)) & res.(['resp' voxClass 'Sz'])(:,:,3)~=0;
    tmp(ind) = 0;
    res.(['resp' voxClass 'Sz'])(:,:,2) = tmp;
end
% Normalize according to std of response from condition 10s since it was acquired in all subject
Cnorm = ismember(taskList,'task_10sPrd1sDur');
normFac = [];
for S = 1:size(res.f,1)
    rStd = [];
    nVox = [];
    for V = 1:length(voxClassList)
        voxClass = voxClassList{V};
        rStd(V) = std(res.(['resp' voxClass]){S,Cnorm});
        nVox(V) = res.(['resp' voxClass 'Sz'])(S,Cnorm,2);
    end
    normFac(S,1) = sum(rStd.*nVox,'omitmissing')./sum(nVox);
end
res.normFac = normFac./mean(normFac);
% Plot all conditions
f3 = figure('WindowStyle','docked');
ht3 = tiledlayout(2,2); ht3.Padding = 'tight'; ht3.TileSpacing = 'tight';
nSub = zeros(1              ,size(res.f,2),length(voxClassList));
nRun = zeros(length(subList),size(res.f,2),length(voxClassList));
nVox = zeros(length(subList),size(res.f,2),length(voxClassList));
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    ax3{V} = nexttile(ht3); hold(ax3{V},'on');
    Cok = false(1,size(res.f,2));
    for T = 1:size(res.f,2)
        if all(isnan(res.f(:,T))); continue; end
        Cok(T) = true;
        ind  = ~cellfun('isempty',res.(['resp' voxClass])(:,T));
        resp = cell2mat(res.(['resp' voxClass])(ind,T)')' ./ res.normFac(ind);
        t    = cell2mat(res.t(ind,T)')';
        nSub(1,T,V) = nnz(ind);
        nRun(ind,T,V) = res.(['resp' voxClass 'Sz'])(ind,T,3);
        nVox(ind,T,V) = res.(['resp' voxClass 'Sz'])(ind,T,2);

        respAv = mean(resp,1,'omitmissing');
        if nSub(1,T,V)==1
            respEr = zeros(size(resp));
        else
            respEr = std(resp,[],1,'omitmissing') ./ sqrt(nSub(1,T,V));
        end
        t = t(1,:)
        hEr{1,T,V} = errorbar(t,respAv,respEr,'color',cMap(T,:))
    end
    if V==2
        tmp = replace(taskList,'task_','')
        legend(ax3{1,V},...
            tmp(Cok)',...
            'AutoUpdate','off','Box','off','interpreter','none','location','southeast');
    end
end
set([hEr{:}],'CapSize',0)
set([ax3{:}],'XLim',[0 20])
grid([ax3{:}],'on')
yLim = get([ax3{:}],'YLim'); set([ax3{:}],'YLim',[-1 1].*max(abs([yLim{:}])));
% Plot 3 conditions
fFlag = 0; % for a 3D render
f4 = figure('WindowStyle','docked');
ht4 = tiledlayout(2,2); ht4.Padding = 'tight'; ht4.TileSpacing = 'tight';
nSub = zeros(1              ,size(res.f,2),length(voxClassList));
nRun = zeros(length(subList),size(res.f,2),length(voxClassList));
nVox = zeros(length(subList),size(res.f,2),length(voxClassList));
hEr = [];
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    ax4{V} = nexttile(ht4); hold(ax4{V},'on');
    
    ismember(taskList,{'task_10sPrd1sDur' 'task_15sPrd1sDur' 'task_20sPrd1sDur' 'task_30sPrd1sDur'});
    
    taskList = {{'task_10sPrd1sDur'} {'task_15sPrd1sDur'} {'task_20sPrd1sDur' 'task_30sPrd1sDur'}}
    for Cx = 1:length(taskList)
        Cok = ismember(taskList,taskList{Cx});
        % Cok = ismember(runCondStimList_tmp,{'task_20sPrd1sDur' 'task_30sPrd1sDur'});
        % Cok = ismember(runCondStimList_tmp,{'task_10sPrd1sDur'});
        % res.(['resp' voxClass])(:,Cok);
        clear resp
        clear t
        clear f
        for S = 1:size(res.f,1)
            tmp       = res.(['resp' voxClass])(S,Cok);
            ind = ~cellfun('isempty',tmp);
            if nnz(Cok)>1
                resp(S,:) = tmp{ind}(1:24);
            else
                resp(S,:) = tmp{ind};
            end
            tmp       = res.t(S,Cok);
            if nnz(Cok)>1
                t(S,:)    = tmp{ind}(1:24);
            else
                t(S,:)    = tmp{ind};
            end
            tmp       = res.f(S,Cok);
            f(S,1) = tmp(~isnan(tmp));
        end
        
        % resp = resp./res.normFac;

        ind = any(isnan(resp),2);
        resp(ind,:) = [];
        t(ind,:)    = [];
        respAv = mean(resp,1);
        respEr = std(resp,[],1) ./ sqrt(size(resp,1));
        t      = t(1,:)
        f      = f(1,:);
        if ~fFlag
            hEr{1,Cx,V} = errorbar(t,respAv,respEr,'color',mean(cMap(Cok,:),1));
        else
            plot3(t,repmat(f,size(t)),respAv,'color',mean(cMap(Cok,:),1));
        end
    end
    if fFlag
        set([ax4{V}],'view',[-15 20]);
    end
    axis tight
    if V==2
        legend(ax4{1,V},...
            {'period=10s' 'period=15s' 'period=20s/30s'},...
            'AutoUpdate','off','Box','off','interpreter','none','location','southeast');
    end
    xlabel('time since stimulus onset (s)')
    if fFlag
        ylabel('stimulus frquency (Hz)')
        zlabel('MR signal change (a.u.) mean+/-sem across subject')
    else
        ylabel('MR signal change (a.u.) mean+/-sem across subject')
    end
    title(voxClass)
end
title(ht4,'group average')
if ~fFlag
    set([hEr{:}],'CapSize',0);
end
grid([ax4{:}],'on')
xLim = get([ax4{:}],'XLim'); xLim = [xLim{:}]; xLim = [min(xLim) max(xLim)];
set([ax4{:}],'XLim',xLim)
if ~fFlag
    yLim = get([ax4{:}],'YLim'); yLim = [-1 1].*max(abs([yLim{:}]));
    set([ax4{:}],'YLim',yLim);
else
    yLim = get([ax4{:}],'YLim'); yLim = [yLim{:}]; yLim = [min(yLim) max(yLim)];
    set([ax4{:}],'YLim',yLim)
    zLim = get([ax4{:}],'ZLim'); zLim = [-1 1].*max(abs([zLim{:}]));
    set([ax4{:}],'ZLim',zLim);

    for V = 1:length(voxClassList)
        plot3([ax4{V}],xLim([1 2 2 1 1]),yLim([1 1 2 2 1]),[0 0 0 0 0],'k')
    end
end
% set([ax4{:}],'YLim',[-1 1].*35);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
return

%%%%%%%%%%%%%
%% Ringing %%
%%%%%%%%%%%%%
verboseThis = 2;

acq  = runCondAcqList {contains(runCondAcqList ,'vfMRI')           };
task = runCondStimList{contains(runCondStimList,'task_50sPrd5sDur')};
res = [];

for S = 1:size(rCond,1)
    if ~isfield(rCond{S}.(acq),task); continue; end
    curCond = rCond{S}.(acq).(task);
    
    % Anatomical voxel selection / classification as vein or artery
    volLabel = MRIload3(rCond{S}.label.(acq).calcarineVessel.f,[],[],0);
    % artery -> 902
    % vein   -> 914
    % unkown -> 30 or 62
    vesMask = volLabel.vol~=0  ; % vessels (including ambiguous aartery vs vein identities)
    artMask = volLabel.vol==902; % arteries
    veiMask = volLabel.vol==914; % veins
    
    % Functional (SPM canon+deriv) voxel selection / classification 
    %%% selection condition 
    pVal            = MRIread(curCond.volActCat.fs.fFullP); pVal = pVal.vol;
    fdrVal          = nan(size(pVal));
    fdrVal(vesMask) = mafdr(pVal(vesMask));
    
    amp = MRIread(curCond.volActCat.fs.fCoefPol); amp = amp.vol;
    % positively activated voxels 
    posMask = abs(amp(:,:,:,2))<pi/2; % & fdrVal<0.05;
    % negatively activated voxels
    negMask = abs(amp(:,:,:,2))>pi/2; % & fdrVal<0.05;
        


    % Extract response timecourses
    % load response ts
    R = 1;
    mri = MRIread(curCond.volRespCat.fs.fRespTs);
    im = permute(mri.vol,[4 1 2 3]);
    res.task{S}{R}       = curCond.label;
    res.respPosArt{S}{R} = mean(im(:,posMask & artMask                         & fdrVal<0.05),2);
    res.respNegArt{S}{R} = mean(im(:,negMask & artMask                         & fdrVal<0.05),2);
    res.respPosVei{S}{R} = mean(im(:,posMask & veiMask                         & fdrVal<0.05),2);
    res.respNegVei{S}{R} = mean(im(:,negMask & veiMask                         & fdrVal<0.05),2);
    res.respPosAmb{S}{R} = mean(im(:,posMask & (vesMask & ~artMask & ~veiMask) & fdrVal<0.05),2);
    res.respNegAmb{S}{R} = mean(im(:,negMask & (vesMask & ~artMask & ~veiMask) & fdrVal<0.05),2);

    tr = mri.tr/1000;
    n  = mri.nframes;
    res.t{S}{R}   = linspace(0,tr*(n-1),n)';
    res.sub{S}{R} = curCond.sub;
end


voxClassList = {'PosArt' 'NegArt' 'PosVei' 'NegVei'};
fFig  = cell(size(res.sub,1));
ht    = cell(size(res.sub,1));
ax    = cell(size(res.sub,1),length(voxClassList));
skipV = false(size(res.sub,2),length(voxClassList));
for S = 1:length(res.sub)
    if isempty(res.sub{S}); skipV(S,:) = true; continue; end
    fFig{S} = figure('WindowStyle','docked');
    ht{S} = tiledlayout(2,2); ht{S}.Padding = 'tight'; ht{S}.TileSpacing = 'tight';
    for V = 1:length(voxClassList)
        voxClass = voxClassList{V};
        t = res.t{S}{R};
        y = res.(['resp' voxClass]){S}{R};
        if isempty(y) || all(isnan(y))
            skipV(S,V) = true;
            nexttile(ht{S}); continue
        else
            ax{S,V} = nexttile(ht{S}); hold(ax{S,V},'on');
        end
        plot(t,y); axis tight
        grid on
        grid minor
        title(voxClass)
    end
    title(ht{S},res.sub{S}{R})
end
yLim = get([ax{~skipV}],'YLim');
yLim = [-1 1].*max(abs([yLim{:}]));
set([ax{~skipV}],'YLim',yLim);


findobj([axX.Children],'line')
get([ax{~cellfun('isempty',ax)}],'XLim')


for i = 1:numel(res.f)
    if isempty(res.f{i})
        res.f{i} = nan;
    end
end
res.f = cell2mat(res.f);

% Plot all
cMap = flip(turbo(size(res.f,2)),1);
voxClassList = {'PosArt' 'NegArt' 'PosVei' 'NegVei'};
fFig1  = cell(size(res.f,1));
ht1 = cell(size(res.f,1));
ax1 = cell(size(res.f,1),length(voxClassList));
f2  = cell(size(res.f,1));
ht2 = cell(size(res.f,1));
ax2 = cell(size(res.f,1),length(voxClassList));
for S = 1:size(res.f,1)
    fFig1{S} = figure('WindowStyle','docked');
    ht1{S} = tiledlayout(2,2); ht1{S,T}.Padding = 'tight'; ht1{S,T}.TileSpacing = 'tight';
    f2{S} = figure('WindowStyle','docked');
    ht2{S} = tiledlayout(2,2); ht2{S,T}.Padding = 'tight'; ht2{S,T}.TileSpacing = 'tight';
    for V = 1:length(voxClassList)
        voxClass = voxClassList{V};
        if all(cellfun('isempty',res.(['resp' voxClass])(S,:))) || all(isnan(cat(1,res.(['resp' voxClass]){S,:})))
            nexttile(ht1{S});
            nexttile(ht2{S});
            continue
        else
            ax1{S,V} = nexttile(ht1{S}); hold(ax1{S,V},'on');
            ax2{S,V} = nexttile(ht2{S}); hold(ax2{S,V},'on');
        end
        Cok = false(1,size(res.f,2));
        t = [];
        y = [];
        f = [];
        for T = 1:size(res.f,2)
            if ~isempty(res.(['resp' voxClass]){S,T}) && any(~isnan(res.(['resp' voxClass]){S,T}))
                plot(ax1{S,V},...
                    res.t{S,T},...
                    res.(['resp' voxClass]){S,T},...
                    'color',cMap(T,:));
                plot3(ax2{S,V},...
                    res.t{S,T},...
                    repmat(res.f(S,T),size(res.t{S,T})),...
                    res.(['resp' voxClass]){S,T},...
                    'color',cMap(T,:)); hold on
                Cok(1,T) = true;
                % t = [t; res.t{S,C}];
                % y = [y; res.(['resp' voxClass]){S,C}];
                % f = [f; repmat(res.f(S,C),size(res.(['resp' voxClass]){S,C}))];
            end
        end
        grid(ax1{S,V},'on')
        grid(ax2{S,V},'on')
        axis(ax1{S,V},'tight')
        axis(ax2{S,V},'tight')
        sz = cell2mat(res.(['resp' voxClass 'Sz'])(S,:)');
        if V==2
            legend(ax1{S,V},...
                strcat(res.task(S,Cok)','; nRun=', cellstr(num2str(sz(:,3)))),...
                'AutoUpdate','off','Box','off');
            legend(ax2{S,V},...
                strcat(res.task(S,Cok)','; nRun=', cellstr(num2str(sz(:,3)))),...
                'AutoUpdate','off','Box','off');
        end
        title(ax1{S,V},[subList{S} '; nVox=' num2str(sz(1,2)) '; ' voxClass])
        title(ax2{S,V},[subList{S} '; nVox=' num2str(sz(1,2)) '; ' voxClass])
        uistack(yline(ax1{S,V},0),'bottom');


        % plot3
        % [T,F] = meshgrid(linspace(min(t),max(t),10),linspace(min(f),max(f),10))
        % Y = interp2(t,f,y,T(:),F(:));
        % surf(t,f,y)
        
        xlabel(ax2{S,V},'time (s)')
        ylabel(ax2{S,V},'stim freq (Hz)')
        zlabel(ax2{S,V},'MR signal change (a.u.)')
    end
    set([ax2{S,:}],'view',[-15 20]);

    yLim1{S} = get([ax1{S,:}],'ylim'); yLim1{S} = [-1 1].*max(abs([yLim1{S}{:}])); set([ax1{S,:}],'ylim',yLim1{S});
    zLim2{S} = get([ax2{S,:}],'zlim'); zLim2{S} = [-1 1].*max(abs([zLim2{S}{:}])); set([ax2{S,:}],'zlim',zLim2{S});
end
drawnow
xLim1 = get([ax1{:}],'xlim'); xLim1 = [min([xLim1{:}]) max([xLim1{:}])]; set([ax1{:}],'xlim',xLim1);
xLim2 = get([ax2{:}],'xlim'); xLim2 = [min([xLim2{:}]) max([xLim2{:}])]; set([ax2{:}],'xlim',xLim2);
yLim2 = get([ax2{:}],'ylim'); yLim2 = [min([yLim2{:}]) max([yLim2{:}])]; set([ax2{:}],'ylim',yLim2);



% Group summary
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    % number of tPts
    if iscell(res.(['resp' voxClass 'Sz'])) % -> S x C x [Nt Nvox Nrun]
        res.(['resp' voxClass 'Sz'])(cellfun('isempty',res.(['resp' voxClass 'Sz']))) = {[nan nan nan]};
        res.(['resp' voxClass 'Sz']) = permute(cell2mat(permute(res.(['resp' voxClass 'Sz']),[1 3 2])),[1 3 2]);
    end
    for T = 1:size(res.f,2)
        ind = ~isnan(res.(['resp' voxClass 'Sz'])(:,T,1));
        if any(ind)
            res.(['resp' voxClass 'Sz'])(:,T,1) = unique(res.(['resp' voxClass 'Sz'])(ind,T,1))
        end
    end
    % number of runs
    for S = 1:size(res.f,1)
        for T = 1:size(res.f,2)
            if isnan(res.f(S,T))
                res.(['resp' voxClass 'Sz'])(S,T,3) = 0;
            end
        end
    end
    % number of voxels
    tmp = res.(['resp' voxClass 'Sz'])(:,:,2);
    ind = isnan(res.(['resp' voxClass 'Sz'])(:,:,2)) & res.(['resp' voxClass 'Sz'])(:,:,3)~=0;
    tmp(ind) = 0;
    res.(['resp' voxClass 'Sz'])(:,:,2) = tmp;
end
% Normalize according to std of response from condition 10s since it was acquired in all subject
Cnorm = ismember(taskList,'task_10sPrd1sDur');
normFac = [];
for S = 1:size(res.f,1)
    rStd = [];
    nVox = [];
    for V = 1:length(voxClassList)
        voxClass = voxClassList{V};
        rStd(V) = std(res.(['resp' voxClass]){S,Cnorm});
        nVox(V) = res.(['resp' voxClass 'Sz'])(S,Cnorm,2);
    end
    normFac(S,1) = sum(rStd.*nVox,'omitmissing')./sum(nVox);
end
res.normFac = normFac./mean(normFac);
% Plot all conditions
f3 = figure('WindowStyle','docked');
ht3 = tiledlayout(2,2); ht3.Padding = 'tight'; ht3.TileSpacing = 'tight';
nSub = zeros(1              ,size(res.f,2),length(voxClassList));
nRun = zeros(length(subList),size(res.f,2),length(voxClassList));
nVox = zeros(length(subList),size(res.f,2),length(voxClassList));
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    ax3{V} = nexttile(ht3); hold(ax3{V},'on');
    Cok = false(1,size(res.f,2));
    for T = 1:size(res.f,2)
        if all(isnan(res.f(:,T))); continue; end
        Cok(T) = true;
        ind  = ~cellfun('isempty',res.(['resp' voxClass])(:,T));
        resp = cell2mat(res.(['resp' voxClass])(ind,T)')' ./ res.normFac(ind);
        t    = cell2mat(res.t(ind,T)')';
        nSub(1,T,V) = nnz(ind);
        nRun(ind,T,V) = res.(['resp' voxClass 'Sz'])(ind,T,3);
        nVox(ind,T,V) = res.(['resp' voxClass 'Sz'])(ind,T,2);

        respAv = mean(resp,1,'omitmissing');
        if nSub(1,T,V)==1
            respEr = zeros(size(resp));
        else
            respEr = std(resp,[],1,'omitmissing') ./ sqrt(nSub(1,T,V));
        end
        t = t(1,:)
        hEr{1,T,V} = errorbar(t,respAv,respEr,'color',cMap(T,:))
    end
    if V==2
        tmp = replace(taskList,'task_','')
        legend(ax3{1,V},...
            tmp(Cok)',...
            'AutoUpdate','off','Box','off','interpreter','none','location','southeast');
    end
end
set([hEr{:}],'CapSize',0)
set([ax3{:}],'XLim',[0 20])
grid([ax3{:}],'on')
yLim = get([ax3{:}],'YLim'); set([ax3{:}],'YLim',[-1 1].*max(abs([yLim{:}])));
% Plot 3 conditions
fFlag = 0; % for a 3D render
f4 = figure('WindowStyle','docked');
ht4 = tiledlayout(2,2); ht4.Padding = 'tight'; ht4.TileSpacing = 'tight';
nSub = zeros(1              ,size(res.f,2),length(voxClassList));
nRun = zeros(length(subList),size(res.f,2),length(voxClassList));
nVox = zeros(length(subList),size(res.f,2),length(voxClassList));
hEr = [];
for V = 1:length(voxClassList)
    voxClass = voxClassList{V};
    ax4{V} = nexttile(ht4); hold(ax4{V},'on');
    
    ismember(taskList,{'task_10sPrd1sDur' 'task_15sPrd1sDur' 'task_20sPrd1sDur' 'task_30sPrd1sDur'});
    
    taskList = {{'task_10sPrd1sDur'} {'task_15sPrd1sDur'} {'task_20sPrd1sDur' 'task_30sPrd1sDur'}}
    for Cx = 1:length(taskList)
        Cok = ismember(taskList,taskList{Cx});
        % Cok = ismember(runCondStimList_tmp,{'task_20sPrd1sDur' 'task_30sPrd1sDur'});
        % Cok = ismember(runCondStimList_tmp,{'task_10sPrd1sDur'});
        % res.(['resp' voxClass])(:,Cok);
        clear resp
        clear t
        clear f
        for S = 1:size(res.f,1)
            tmp       = res.(['resp' voxClass])(S,Cok);
            ind = ~cellfun('isempty',tmp);
            if nnz(Cok)>1
                resp(S,:) = tmp{ind}(1:24);
            else
                resp(S,:) = tmp{ind};
            end
            tmp       = res.t(S,Cok);
            if nnz(Cok)>1
                t(S,:)    = tmp{ind}(1:24);
            else
                t(S,:)    = tmp{ind};
            end
            tmp       = res.f(S,Cok);
            f(S,1) = tmp(~isnan(tmp));
        end
        
        % resp = resp./res.normFac;

        ind = any(isnan(resp),2);
        resp(ind,:) = [];
        t(ind,:)    = [];
        respAv = mean(resp,1);
        respEr = std(resp,[],1) ./ sqrt(size(resp,1));
        t      = t(1,:)
        f      = f(1,:);
        if ~fFlag
            hEr{1,Cx,V} = errorbar(t,respAv,respEr,'color',mean(cMap(Cok,:),1));
        else
            plot3(t,repmat(f,size(t)),respAv,'color',mean(cMap(Cok,:),1));
        end
    end
    if fFlag
        set([ax4{V}],'view',[-15 20]);
    end
    axis tight
    if V==2
        legend(ax4{1,V},...
            {'period=10s' 'period=15s' 'period=20s/30s'},...
            'AutoUpdate','off','Box','off','interpreter','none','location','southeast');
    end
    xlabel('time since stimulus onset (s)')
    if fFlag
        ylabel('stimulus frquency (Hz)')
        zlabel('MR signal change (a.u.) mean+/-sem across subject')
    else
        ylabel('MR signal change (a.u.) mean+/-sem across subject')
    end
    title(voxClass)
end
title(ht4,'group average')
if ~fFlag
    set([hEr{:}],'CapSize',0);
end
grid([ax4{:}],'on')
xLim = get([ax4{:}],'XLim'); xLim = [xLim{:}]; xLim = [min(xLim) max(xLim)];
set([ax4{:}],'XLim',xLim)
if ~fFlag
    yLim = get([ax4{:}],'YLim'); yLim = [-1 1].*max(abs([yLim{:}]));
    set([ax4{:}],'YLim',yLim);
else
    yLim = get([ax4{:}],'YLim'); yLim = [yLim{:}]; yLim = [min(yLim) max(yLim)];
    set([ax4{:}],'YLim',yLim)
    zLim = get([ax4{:}],'ZLim'); zLim = [-1 1].*max(abs([zLim{:}]));
    set([ax4{:}],'ZLim',zLim);

    for V = 1:length(voxClassList)
        plot3([ax4{V}],xLim([1 2 2 1 1]),yLim([1 1 2 2 1]),[0 0 0 0 0],'k')
    end
end
% set([ax4{:}],'YLim',[-1 1].*35);


%% %%%%%%%%%%
return


%% %%%%%%%%%%%%%%%%%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Visualize Individual Runs  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
S = 1;
acq  = runCondAcqList{ contains(runCondAcqList ,'vfMRI'  )};
task = runCondStimList{contains(runCondStimList,'task_50sPrd5sDur')};


r = 1
volResp     = rCond{S}.(acq).(task).volRespCat;
volAct      = rCond{S}.(acq).(task).volActCat;
volTs       = rCond{S}.(acq).(task).volTs(r);
dsgn        = rCond{S}.(acq).(task).dsgn;
mask        = rCond{S}.label.vfMRI.calcarineVessel.f;

close all
volPsd  = rCond{S}.(acq).(task).volPsd_K5_win20(r);
[volPsd,volTs,volResp,volAct] = plotSpecAll3(volPsd,volTs,volResp,volAct,dsgn,mask,[],0.05)
volPsd  = rCond{S}.(acq).(task).volPsd_K10_win20(r);
[volPsd,volTs,volResp,volAct] = plotSpecAll3(volPsd,volTs,volResp,volAct,dsgn,mask,[],0.05)
volPsd  = rCond{S}.(acq).(task).volPsd_K15_win20(r);
[volPsd,volTs,volResp,volAct] = plotSpecAll3(volPsd,volTs,volResp,volAct,dsgn,mask,[],0.05)

return


for r = 1:length(volPsd)
    tryL2svd(volPsd(r))
    plotSpecAll2(volPsd(r),volTs(r),volResp(r),volTs(r).dsgn,volAnat.roi{roiInd}.f,[],0.05)
end

for r = 1:length(volPsd)
    plotSpecAll2(volPsd(r),volTs(r),volResp(r),volTs(r).dsgn,volAnat.roi{roiInd}.f,[],0.05)

    figure('WindowStyle','docked');
    winInd = 1;
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);
    set(gca,'YScale','log')
    grid on; grid minor
    hold on

    winInd = round(size(volPsd(r).psdTrialGramMD.t,7)/2);
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);

    winInd = size(volPsd(r).psdTrialGramMD.t,7);
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);

    legend({'early' 'mid' 'late'})
    ax = gca;
    yLim = get(ax.Children,'YData'); yLim = min(cat(1,yLim{:}),[],1); yLim = min(yLim(f>0.05)); tmp = ylim; yLim(2) = tmp(2); ylim(yLim);
end

return

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%
%% Freeview %%
%%%%%%%%%%%%%%

S = 1;
rCond{S};
popp2(sesPhys{end})

5
S = 1;
curDir = rCond{S}.vfMRI.task_50sPrd5sDur.wd{1};
dir(fullfile(curDir,'sub-vsmDrivenP1_ses-1_task-50sPrd5sDur_run-*_angio','*'))
derivDir = '/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven4/bids/sub-vsmDrivenP1/ses-1/derivatives/set-vfMRI';


cmd = {srcFs};
cmd{end+1} = 'freeview \';
tmp = fullfile('/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven4/bids/sub-vsmDrivenP1/ses-1/derivatives/set-vfMRI/sub-vsmDrivenP1_ses-1_task-50sPrd5sDur_run-av_angio',...
    'cond-visOn_base.nii.gz');
cmd{end+1} = [tmp ' \'];
tmp = fullfile('/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven4/bids/sub-vsmDrivenP1/ses-1/derivatives/set-vfMRI/sub-vsmDrivenP1_ses-1_task-50sPrd5sDur_run-av_angio',...
    'cond-visOn_resp.nii.gz');
cmd{end+1} = [tmp ' \'];
tmp = fullfile('/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven4/bids/sub-vsmDrivenP1/ses-1/derivatives/set-vfMRI/sub-vsmDrivenP1_ses-1_task-50sPrd5sDur_run-av_angio',...
    'cond-visOn_respF.nii.gz');
cmd{end+1} = [tmp ':colormap=heat'];
clipboard("copy",strjoin(cmd,newline))

dir(tmp)
%% %%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PPG to brain vessel coherence %%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

S = 1;
r = 1;
volTs = rCond{S}.vfMRI.task_50sPrd5sDur.volTs(r).mri;
Fstim = 1/mean(diff(rCond{S}.vfMRI.task_50sPrd5sDur.dsgn.onsetList));
volTs = MRIload2(volTs);
physTs = rCond{S}.vfMRI.task_50sPrd5sDur.phys(r);

% volAnat = runCond{S}.vfMRI.task_50sPrd5sDur.volAnatSub
% roi = [volAnat.roi{:}];
% ind = ismember({roi.label},'vesselCalcarineRoi01a');

% volTs = vol2vec(volTs,volAnat.roi{ind}.f,1)
fMask = '/autofs/space/takoyaki_001/users/proulxs/vsmDriven/doIt_vsmDriven4/bids/sub-vsmDrivenP1/ses-cat/derivatives/center_vesselRoi01a.nii.gz';
volTs = vol2vec(volTs,fMask,1);


figure('WindowStyle','docked');
prd   = [60 30 20 15 12 10];
prdTr = round(prd./tr);
prd   = prdTr.*tr;
x = 1./prd;
xline(x,'Color','k')
y = repmat(mean(ylim),size(x));
text(x,y,num2str(prd','%0.2f'))
xline(1/50,'g')

xlim([0 0.6])
grid on
ax = gca;
ax.XMinorGrid = 'on'
ax.XMinorTick = 'on'

prd2 = prd([2 4 6]);
xline(1./prd2,'r')
prd2Tr = prdTr([2 4 6]);




tr = volTs.tr/1000;

1./(1./15 + diff(1./[15 10])/2)



1./(1./20 - diff(1./[20 15]))
1./linspace(0,0.1,6)



for Kmri = 3:10

    ax = {};
    figure('WindowStyle','docked');
    ht = tiledlayout(4,1); ht.Padding = 'tight'; ht.TileSpacing = 'tight';
    ax{end+1} = nexttile([2 1]);

    % MRI
    dMri = volTs.vec;
    tMri = volTs.t;
    FsMri = 1 / (volTs.tr/1000);
    dMri = dtrnd2(dMri,1/FsMri);
    dMri = dMri./std(dMri);

    % Kmri = 5;
    nMri = size(dMri,1);
    Tmri = (nMri-1)/FsMri;
    [TWmri,Wmri,Kmri] = K2W(Tmri,Kmri);
    paramMri.Fs = FsMri;
    paramMri.tapers = [TWmri Kmri];
    paramMri.err = [1 0.05];
    [psdMri,fMri,Serr] = mtspectrumc(dMri,paramMri);
    hMriPsd = plot(fMri,psdMri,'k'); hold on
    hMriPsdEr = plot(fMri,Serr,':k'); hold on


    % physio
    chanInd = ismember(physTs.chanLabel,'cardiac');
    d = physTs.vec(:,chanInd);
    n = size(d,1);
    Fs = physTs.Fs(chanInd);
    % t0 = physTs.t0(1,chanInd);
    t = linspace(0,(n-1)/Fs,n);
    % t = physTs.t(:,:,:,r) - sum([hour(physTs.blocktimes)*60*60 minute(physTs.blocktimes)*60 second(physTs.blocktimes)]);
    d = dtrnd2(d,1/Fs);
    d = d./std(d);

    K = 22;
    T = (n-1)/Fs;
    [TW,W,K] = K2W(T,K);
    param.Fs = Fs;
    param.tapers = [TW K];
    [psd,f] = mtspectrumc(d,param);
    hPhysPsd = plot(f,psd,'b'); hold on

    ax{end}.YScale = 'log'; grid on
    ax{end}.XMinorGrid = 'on'
    xlim([0 2.5])


    % physio downsample
    dDs = interp1(t,d,tMri);
    FsDs = FsMri;
    nDs = nMri;
    Tds = (nMri-1)/FsMri;
    Kds = Kmri;
    [TWds,Wds,Kds] = K2W(T,K);
    paramDs.Fs = FsDs;
    paramDs.tapers = [TWds Kds];
    [psdDs,fDs] = mtspectrumc(dDs,paramDs);
    hPhysPsdDs = plot(fDs,psdDs,'-.b'); hold on

    % xline(FsMri/2,'k')
    hHarm1 = xline(1.17111,'Color','r')
    hHarm2 = xline(1.17111*2,'Color','r','LineStyle','--')
    hHarm3 = xline(1.17111*3,'Color','r','LineStyle',':')
    hStim  = xline(Fstim,'Color','g');

    xline(FsMri/2 - (1.17111 - FsMri/2),'Color','r')
    xline(FsMri/2 - (abs((FsMri/2 - (1.17111*2 - FsMri/2))) - FsMri/2),'Color','r','LineStyle','--')
    xline(FsMri/2 - (abs(FsMri/2 - (abs((FsMri/2 - (1.17111*3 - FsMri/2))) - FsMri/2)) - FsMri/2),'Color','r','LineStyle',':')
    ylabel('psd')

    legend(...
        [hMriPsd
        hMriPsdEr(1)
        hPhysPsd
        hPhysPsdDs
        hStim
        hHarm1
        hHarm2
        hHarm3],...
        {'MRI' 'MRI 95%CI' ['cardiac (K=' num2str(K) ')'] 'cardiac ds to mri' 'stimulus' 'cardiacHarm1' 'cardiacHarm2' 'cardiacHarm3'})

    uistack([hHarm1 hHarm2 hHarm3],'bottom')

    % coherence
    paramMri.err = [2 0.05];
    [T,phi,S12,S1,S2,f,confC,phistd,Cerr]=coherencyc(dMri,dDs,paramMri);
    ax{end+1} = nexttile;
    hCoh = plot(f,T,'k'); hold on
    hCohEr = plot(f,Cerr,':k')
    hW = line(0.1 + [-Wmri Wmri],0.5.*[1 1],'LineWidth',5,'color','g')
    ylim([0 1])
    grid on
    hCohConf = yline(confC,'m')
    ax{end}.XMinorGrid = 'on'
    xline(1.17111,'Color','r')
    xline(1.17111*2,'Color','r','LineStyle','--')
    xline(1.17111*3,'Color','r','LineStyle',':')
    xline(Fstim,'Color','g');
    xline(FsMri/2 - (1.17111 - FsMri/2),'Color','r')
    xline(FsMri/2 - (abs((FsMri/2 - (1.17111*2 - FsMri/2))) - FsMri/2),'Color','r','LineStyle','--')
    xline(FsMri/2 - (abs(FsMri/2 - (abs((FsMri/2 - (1.17111*3 - FsMri/2))) - FsMri/2)) - FsMri/2),'Color','r','LineStyle',':')
    ylabel('coherence')

    legend(...
    [hCoh
    hCohEr(1)
    hCohConf
    hW],...
    {'MRI to cardiac coherence' '95%conf' 'thresh' '2W'})
    uistack(hW,'bottom')

    ax{end+1} = nexttile;
    hPhase = plot(f,phi,'k')
    grid on
    ylim([-pi pi])
    xline(1.17111,'Color','r')
    xline(1.17111*2,'Color','r','LineStyle','--')
    xline(1.17111*3,'Color','r','LineStyle',':')
    xline(Fstim,'Color','g');
    xline(FsMri/2 - (1.17111 - FsMri/2),'Color','r')
    xline(FsMri/2 - (abs((FsMri/2 - (1.17111*2 - FsMri/2))) - FsMri/2),'Color','r','LineStyle','--')
    xline(FsMri/2 - (abs(FsMri/2 - (abs((FsMri/2 - (1.17111*3 - FsMri/2))) - FsMri/2)) - FsMri/2),'Color','r','LineStyle',':')
    legend(hPhase,{'MRI to cardiac coherence phase'})



    ylabel('phase')
    set([ax{:}],'XLim',[0 1.3])
    set([ax{:}],'XTick',0:0.1:1.3)
    drawnow

    xlabel(ht,'Hz')
    
    title(ht,['single 5-min run, K=' num2str(Kmri)])
end
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Cardiac phase-locking to stimulus %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

chanInd = 1;
taskList = {'task_50sPrd5sDur' 'task_20sPrd1sDur' 'task_15sPrd1sDur' 'task_10sPrd1sDur'};
for s = 1:2
    for tInd = 1:length(taskList)
        task = taskList{tInd};
        if isempty(rCond{s}.vfMRI.(task).physRuns); continue; end
        Fs = rCond{s}.vfMRI.(task).physRuns.samplerate(1);
        onsetList = rCond{s}.vfMRI.(task).dsgn.onsetList;
        isiSec = mean(diff(onsetList)); % isiSec = 47.88; % isi = mean(diff(onsetList));
        isiPts = round(isiSec*Fs);
        isiSec = isiPts/Fs;
        card  = zeros(isiPts,length(onsetList),size(rCond{s}.vfMRI.(task).physRuns.vec,4));
        cardM = zeros(isiPts,1                ,1                                           );
        smWinSec    = 0.05;
        smWinSecPts = smWinSec*Fs;
        for r = 1:size(rCond{s}.vfMRI.(task).physRuns.vec,4)
            t    = rCond{s}.vfMRI.(task).physRuns.t(:,1,1,r);
            t    = t - t(1);
            for e = 1:length(onsetList)
                [~,iS] = min(abs(t-onsetList(e)));
                iE = iS + isiPts - 1;
                card(:,e,r) = zscore(rCond{s}.vfMRI.(task).physRuns.vec(iS:iE,chanInd,1,r));
                cardM = cardM + card(:,e,r);
                card(:,e,r) = smooth(card(:,e,r),smWinSecPts);
            end
        end
        cardM = cardM./(size(rCond{s}.vfMRI.(task).physRuns.vec,4)*length(onsetList));
        cardM = smooth(cardM,smWinSecPts);
        figure('WindowStyle','docked');
        t = (0:1/Fs:(isiSec-1/Fs))';
        % hP = plot(t,mean(card(:,:),2));
        hP = plot(t,cardM);
        hP.LineWidth = 3; hP.Color = 'r';
        hold on
        hPx = plot(t,card(:,:),'Color',[0 0 0 0.15]);
        % xlim([0 15])
        uistack(hP,'top')
        grid on
        grid minor
        title(['sub-' num2str(s) '; ' replace(task,'_','-') '; ' num2str(size(rCond{s}.vfMRI.(task).physRuns.vec,4)) 'runs, ' num2str(length(onsetList)) 'trial each'])
        xlim([0 40])
        ylim([-2 4])

        xlabel('time since stimulus onset (s)')
        ylabel('ppg trace (z-scored run by run)')
        legend([hP hPx(1)],{'trial-triggered average' ['single-trial (n=' num2str(length(hPx)) ')']},'AutoUpdate','off')

        x = [0 mean(rCond{s}.vfMRI.(task).dsgn.ondurList)];
        y = ylim; y = y([1 1]);
        plot(x,y,'k','LineWidth',10)

        outDir = fullfile(info.bidsDir,['sub-' rCond{s}.vfMRI.(task).sub],'ses-cat'); if ~exist(outDir,'dir'); mkdir(outDir); end
        outFile = [task '_run-cat_trialTriggeredCardiac.fig'];
        drawnow
        % saveas(gcf,fullfile(outDir,outFile))
    end
end

t    = rCond{s}.vfMRI.(task).physRuns.t(:,1,1,r);
card = zscore(rCond{s}.vfMRI.(task).physRuns.vec(:,chanInd,1,r));
t    = t(10:end);
card = card(10:end);
cardSm = smooth(card,200);

a = findpeaks(cardSm,2);
figure('WindowStyle','docked');
plot(t,cardSm)
xline(t(a.loc))

TR = 0.84;
[hr, hrv_rmsd] = HRcal(t(a.loc),10/TR,TR,6,0);



tmp.loc

% chanInd = 1;
% taskList = {'task_50sPrd5sDur' 'task_20sPrd1sDur' 'task_15sPrd1sDur' 'task_10sPrd1sDur'};
% dsFac = 500;
% for s = 2
%     for tInd = 1
%         task = taskList{tInd};
%         if isempty(runCond{s}.vfMRI.(task).physRuns); continue; end
%         Fs = runCond{s}.vfMRI.(task).physRuns.samplerate(1);
%         for r = 1 %:size(runCond{s}.vfMRI.(task).physRuns.vec,4)
%             t    = runCond{s}.vfMRI.(task).physRuns.t(:,1,1,r);
%             t    = t - t(1);
%             card = runCond{s}.vfMRI.(task).physRuns.vec(:,chanInd,1,r);
%             nfft = length(card);
%             nfft = 2^(nextpow2(nfft)-1);
%             W = 0.05;
%             T = length(card)./Fs;
%             TW = T.*W;
%             K = round(TW*2-1);
%             TW = (K+1)/2;
%             W = TW/T;
%             disp(['computing mt spectum with ' num2str(K) ' tapers; run ' num2str(r) '/' num2str(size(runCond{s}.vfMRI.(task).physRuns.vec,4))])
%             tic
%             [pw,f] = pmtm(card-mean(card),TW,nfft,Fs);
% 
%             figure('WindowStyle','docked');
%             plot(f,pw)
%             ax = gca;
%             ax.YScale = 'log';
%             xlim([0 10])
%             hold on
% 
%             tq = downsample(t,dsFac);
%             cardq = interp1(t,card,downsample(t,dsFac));
%             nfft = length(cardq);
%             nfft = 2^(nextpow2(nfft)-1);
%             [pw,f] = pmtm(cardq-mean(cardq),TW,nfft,Fs/dsFac);
%             plot(f,pw)
% 
% 
%             grid on
%             grid minor
%             title(['sub-' num2str(s) '; ' replace(task,'_','-') '; ' num2str(size(runCond{s}.vfMRI.(task).physRuns.vec,4)) 'runs, ' num2str(length(onsetList)) 'trial each'])
%             drawnow
%         end
%     end
% end
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Load and run on demand example %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
do.loadIt  = 0;
do.doIt    = 1;
do.saveIt  = 0;
do.writeIt = 1;

for S = 1:5
    task = runCondStimList{contains(runCondStimList,'task_50sPrd5sDur')};
    acq  = runCondAcqList{ contains(runCondAcqList ,'vfMRI'  )};
    if ~isfield(rCond{S}.(acq),task) || isempty(rCond{S}.(acq).(task)); continue; end

    %anat
    veMask = rCond{S}.label.vfMRI.calcarineVessel.f;
    hdMask = rCond{S}.mask{1}.head.mri;
    % volAnat = runCond{S}.(runCondAcq).(runCondStim).volAnatSub;
    % volAnat.roi{end+1} = volAnat.roi{end};
    % volAnat.roi{end}.label = 'calcarine';
    % volAnat.roi{end}.f = fullfile(fileparts(replace(volAnat.roi{end}.f,'.nii.gz','')),'sesAvCat_cat_av_preproc_calcarineMask.nii.gz');
    % roiLabelList = [volAnat.roi{:}]; roiLabelList = {roiLabelList.label}';
    % % roiLabel = 'calcarine';
    % roiLabel = 'vesselCalcarine';
    % roiInd = ismember(roiLabelList,roiLabel);

    %ts
    volTs = rCond{S}.(acq).(task).volTs;
    if ~isfield(volTs,'dsgn') && isfield(rCond{S}.(acq).(task),'dsgn')
        [volTs.dsgn] = deal(rCond{S}.(acq).(task).dsgn);
    end
    for r = 1:length(volTs)
        volTs(r) = MRIload2(volTs(r));
    end

    %resp
    forceThis   = 1;
    verboseThis = 2;
    info.doCat  = 1;
    info.doRun  = 0;
    info.doMov  = 1;
    if isfield(volTs,'dsgn') && ~isempty(volTs(1).dsgn.onsetList)
        % [volResp, ~, info] = volTsGetResp3(do,info,volTs,[],volAnat,forceThis,verboseThis);
        [volResp, ~, info] = volTsGetResp3(do,info,volTs,[],hdMask,forceThis,verboseThis);
        % fIn = [volTs.mri]; fIn = {fIn.fspec}';
        % fld = JSNread(fIn,[]);

    else
        volResp = [];
    end
end
strjoin({volResp.base.fspec
volResp.ts.fspec
volResp.F.fspec},' ')
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% plot responses for each vessels %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% close all
figure('WindowStyle','docked');

volResp.ts = MRIload2(volResp.ts,volAnat.roi{roiInd}.f);
volResp.F = MRIload2(volResp.F,volAnat.roi{roiInd}.f);

roiList      = [volAnat.roi{4:end-1}];
roiLabelList = {roiList.label}';
roiList      = {roiList.f}';

row = floor(sqrt(length(roiList)));
col = ceil(length(roiList)/row);
ht = tiledlayout(row,col); ht.TileSpacing = 'tight'; ht.Padding = 'tight';
for roi = 1:length(roiList)
    nexttile
    mask = MRIread(roiList{roi});
    Fq  = vol2vec(vec2vol(volResp.Fq),mask.vol,1);
    F   = vol2vec(vec2vol(volResp.F ),mask.vol,1);
    for c = 1:length(volResp.ts)
        t  = volResp.ts(c).t;
        ts = vol2vec(vec2vol(volResp.ts(c)),mask.vol,1);
        ts = mean(ts.vec(:,Fq.vec<0.05),2);
        plot(t,ts); hold on
        xlabel('time (s)')
        ylabel('MR signal (a.u.)')
    end
    F   = mean(F.vec(:,Fq.vec<0.05));
    title([replace(roiLabelList{roi},'vesselCalcarineRoi','') '; ' num2str(nnz(Fq.vec<0.05)) 'vox; F_{av}=' num2str(F)])
    grid on
    grid minor
    ylim([-180 100])
end
legend({'stimTrial' 'catchTrial'})
title(ht,[volTs(1).mri.sub '; ' task '; ' num2str(length(volTs)) 'runs'],'interpreter','none')


ax = gcf;
ax = findobj(ax.Children.Children,'type','axes');
% set(ax,'XLim',[0 20])
set(ax,'YLim',[-175 175])
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% plot ts for each vessels %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
volResp.F = MRIload2(volResp.F,volAnat.roi{roiInd}.f);
volTsX = MRIload2([volTs.mri]',volAnat.roi{roiInd}.f);

% close all
figure('WindowStyle','docked');

roiList      = [volAnat.roi{4:end-1}];
roiLabelList = {roiList.label}';
roiList      = {roiList.f}';

row = floor(sqrt(length(roiList)));
col = ceil(length(roiList)/row);
ht = tiledlayout(row,col); ht.TileSpacing = 'tight'; ht.Padding = 'tight';
for roi = 1:length(roiList)
    nexttile
    mask = MRIread(roiList{roi});
    Fq  = vol2vec(vec2vol(volResp.Fq),mask.vol,1);
    F   = vol2vec(vec2vol(volResp.F ),mask.vol,1);
    t  = volTsX(1).t + volTsX(1).nDummyRemoved*volTsX(1).tr/1000;
    ts = [];
    for r = 1:length(volTsX)
        tsX = vol2vec(vec2vol(volTsX(r)),mask.vol,1);
        ts(:,r) = mean(tsX.vec(:,Fq.vec<0.05),2);
    end
    plot(t,mean(ts,2),'k'); hold on
    xlabel('time (s)')
    ylabel('MR signal (a.u.)')
    F   = mean(F.vec(:,Fq.vec<0.05));
    title([replace(roiLabelList{roi},'vesselCalcarineRoi','') '; ' num2str(nnz(Fq.vec<0.05)) 'vox; F_{av}=' num2str(F)])
    grid on
    grid minor
    % ylim([-180 100])
    xline(volResp.dsgn.onsetList(volResp.dsgn.condList==1),'b')
    xline(volResp.dsgn.onsetList(volResp.dsgn.condList==2),'r')
end
title(ht,[volTs(1).mri.sub '; ' task '; ' num2str(length(volTs)) 'runs'],'interpreter','none')
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%
%% Behavior %%
%%%%%%%%%%%%%%
do.loadIt  = 0;
do.doIt    = 1;
do.saveIt  = 0;
do.writeIt = 0;

S = 2;
task = runCondStimList{contains(runCondStimList,'task_20sPrd1sDur')};
acq  = runCondAcqList{ contains(runCondAcqList ,'vfMRI'  )};

%anat
volAnat = rCond{S}.(acq).(task).volAnatSub;
volAnat.roi{end+1} = volAnat.roi{end};
volAnat.roi{end}.label = 'calcarine';
volAnat.roi{end}.f = fullfile(fileparts(replace(volAnat.roi{end}.f,'.nii.gz','')),'sesAvCat_cat_av_preproc_calcarineMask.nii.gz');
roiLabelList = [volAnat.roi{:}]; roiLabelList = {roiLabelList.label}';
% roiLabel = 'calcarine';
roiLabel = 'vesselCalcarine';
roiInd = ismember(roiLabelList,roiLabel);

%ts
volTs = rCond{S}.(acq).(task).volTs;
if ~isfield(volTs,'dsgn') && isfield(rCond{S}.(acq).(task),'dsgn')
    [volTs.dsgn] = deal(rCond{S}.(acq).(task).dsgn);
end
for r = 1:length(volTs)
    volTs(r).bhvr = rCond{S}.(acq).(task).bhvr(r);
end


for r = 1:length(volTs)
    fMask = volAnat.roi{roiInd}.f;
    h(r) = plotSpec3([],volTs(r),'psd',volTs(r).dsgn,fMask,[],[],[]);
    h(r).Title.String = [h(r).Title.String '; perf=' num2str(str2num(volTs(r).bhvr.performance))];
end
yLim = get(h,'YLim'); yLim = [yLim{:}]; yLim = [min(yLim) max(yLim)];
set(h,'YLim',yLim)

mri = [volTs.mri];
mri.ses


%% %%%%%%%%%%%



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% vRF (vessel Response Function) %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
do.loadIt  = 0;
do.doIt    = 1;
do.saveIt  = 0;
do.writeIt = 1;

S = 1;
task = runCondStimList{contains(runCondStimList,'task_50sPrd5sDur')};
acq  = runCondAcqList{ contains(runCondAcqList ,'vfMRI'  )};

%anat
volAnat = rCond{S}.(acq).(task).volAnatSub;
% volAnat.roi{end+1} = volAnat.roi{end};
% volAnat.roi{end}.label = 'calcarine';
% volAnat.roi{end}.f = fullfile(fileparts(replace(volAnat.roi{end}.f,'.nii.gz','')),'sesAvCat_cat_av_preproc_calcarineMask.nii.gz');
roiLabelList = [volAnat.roi{:}]; roiLabelList = {roiLabelList.label}';
% roiLabel = 'calcarine';
roiLabel = 'vesselCalcarineRoi08ax';
% roiLabel = 'vesselCalcarine';
roiInd = ismember(roiLabelList,roiLabel);

volAnatX = volAnat;
volAnatX.roi{roiInd}.mri = MRIload2(MRIload2(volAnatX.roi{roiInd}.f));
volAnatX.roi{roiInd}.mri = vec2vol(volAnatX.roi{roiInd}.mri);
volAnatX.roi{roiInd}.mri.vol2vec(207,211) = true;
volAnatX.roi{roiInd}.mri.vol2vec(208,210) = true;
volAnatX.roi{roiInd}.mri.vol2vec(206,212) = true;
volAnatX.roi{roiInd}.mri.vol2vec(206,213) = true;
volAnatX.roi{roiInd}.mri.vol2vec(209,213) = true;
volAnatX.roi{roiInd}.mri.vol2vec(210,212) = true;
volAnatX.roi{roiInd}.mri.vol2vec(211,209) = true;
volAnatX.roi{roiInd}.mri = vol2vec(volAnatX.roi{roiInd}.mri);
volAnatX.roi{roiInd}.mri.vec(:) = true;
volAnatX.roi{roiInd}.mri = vec2vol(volAnatX.roi{roiInd}.mri);
volAnatX.roi{roiInd}.mri.vol(isnan(volAnatX.roi{roiInd}.mri.vol)) = false;


%ts
volTs = rCond{S}.(acq).(task).volTs;
if ~isfield(volTs,'dsgn') && isfield(rCond{S}.(acq).(task),'dsgn')
    [volTs.dsgn] = deal(rCond{S}.(acq).(task).dsgn);
end
for r = 1:length(volTs)
    volTs(r) = MRIload2(volTs(r),volAnatX.roi{roiInd}.mri);
end

% ses = [volTs.mri];
% cat(1,ses.ses)

%resp
forceThis   = 1;
verboseThis = 1;
for r = 1:length(volTs)
    [volResp(r), ~, info] = volTsGetResp3(do,info,volTs(r),[],volAnat,forceThis,verboseThis);
end




mask = volAnatX.roi{roiInd}.f;

info.method = 'uniSVD'; % 'uniSVD' 'multiSVD' 'canon' 'pls'
r = 1;
MVPA(volTs(r),info,mask,volResp(r))

info.method = 'multiSVD'; % 'uniSVD' 'multiSVD' 'canon' 'pls'
MVPA(volTs,info,mask,volResp)

info.method = 'canon'; % 'uniSVD' 'multiSVD' 'canon' 'pls'
MVPA(volTs,info,mask,volResp)

info.method = 'pls'; % 'uniSVD' 'multiSVD' 'canon' 'pls'
MVPA(volTs,info,mask,volResp)


roiIndList = [4 9 11 14];
for roiInd = 1:length(roiIndList)
    mask = volAnatX.roi{roiIndList(roiInd)}.f;
    info.method = 'uniSVD'; % 'uniSVD' 'multiSVD' 'canon' 'pls'
    info.label = volAnatX.roi{roiIndList(roiInd)}.label;
    MVPA(volTs,info,mask,[]);
end


%mt
K = 4;
extra.Kf = [1 2 3] .* 1/mean(diff(volTs(r).dsgn.onsetList));
W = [];
win = inf;
verboseThis = 1;
r = 1;
volPsd(r) = runFullMT3(volTs(r),W,K,win,[],[],volAnatX.roi{roiInd}.mri,extra,[],[],verboseThis,[],[])';

M = 1;
ax = {};
figure('WindowStyle','docked');
imagesc(volTs(r).mri.imMean);
ax{end+1} = gca;
ax{end}.Colormap = gray;
ax{end}.DataAspectRatio = [1 1 1];
ax{end}.PlotBoxAspectRatio = [1 1 1];
figure('WindowStyle','docked');
im = zeros(size(volTs(r).mri.vol2vec));
im(volTs(r).mri.vol2vec) = volPsd(r).svdXfreq.spSV(:,:,:,:,:,:,:,M);
imagesc(abs(im));
ax{end+1} = gca;
ax{end}.DataAspectRatio = [1 1 1];
ax{end}.PlotBoxAspectRatio = [1 1 1]; colorbar
figure('WindowStyle','docked');
imagesc(angle(im));
ax{end+1} = gca;
ax{end}.Colormap = hsv;
ax{end}.DataAspectRatio = [1 1 1];
ax{end}.PlotBoxAspectRatio = [1 1 1];
ax{end}.CLim = [-pi pi]; colorbar
linkaxes([ax{:}])

figure('WindowStyle','docked');
x = squeeze(imag(volPsd(r).svdXfreq.spSV(:,:,:,:,:,:,:,M)));
y = squeeze(real(volPsd(r).svdXfreq.spSV(:,:,:,:,:,:,:,M)));
scatter(x,y);
lim = [-1 1].*max(abs([x; y]));
xlim(lim); ylim(lim);
ax = gca; ax.DataAspectRatio = [1 1 1];
grid on; grid minor;
b0 = x\y;
yhat0=b0*[0; x]; 
hold on
plot([0; x],yhat0)
b0 = (x.^2)\(y.^2);
yhat0=b0*[0; x]; 
hold on
plot([0; x],yhat0)
b0 = (x.^3)\(y.^3);
yhat0=b0*[0; x]; 
hold on
plot([0; x],yhat0)


plotSpec3([],volPsd(r),'coh',volTs(r).dsgn,volAnatX.roi{roiInd}.f);


ax = {};
for K = 2:10
    W = [];
    win = inf;
    verboseThis = 1;
    r = 1;
    volPsd(r) = runFullMT3(volTs(r),W,K,win,[],[],volAnatX.roi{roiInd}.f,[],[],[],verboseThis,[],[])';
    plotSpec3([],volPsd(r),'coh',volTs(r).dsgn,volAnatX.roi{roiInd}.f);

    ax{end+1} = gca;
    axL = findobj(ax{end}.Children,'Type','ConstantLine');
    axL(end+1) = copyobj(axL(1),ax{end}); axL(end).Value = axL(1).Value*2;
    axL(end+1) = copyobj(axL(1),ax{end}); axL(end).Value = axL(1).Value*3;
    axL(end+1) = copyobj(axL(1),ax{end}); axL(end).Value = axL(1).Value*4;
end
yLim = get([ax{:}],'YLim'); yLim = [yLim{:}]; yLim = [min(yLim) max(yLim)];
set([ax{:}],'YLim',yLim);


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Visualize Individual Runs  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
do.loadIt  = 0;
do.doIt    = 1;
do.saveIt  = 0;
do.writeIt = 1;

S = 1;
task = runCondStimList{contains(runCondStimList,'task_50sPrd5sDur')};
acq  = runCondAcqList{ contains(runCondAcqList ,'vfMRI'  )};

%anat
volAnat = rCond{S}.(acq).(task).volAnatSub;
volAnat.roi{end+1} = volAnat.roi{end};
volAnat.roi{end}.label = 'calcarine';
volAnat.roi{end}.f = fullfile(fileparts(replace(volAnat.roi{end}.f,'.nii.gz','')),'sesAvCat_cat_av_preproc_calcarineMask.nii.gz');
roiLabelList = [volAnat.roi{:}]; roiLabelList = {roiLabelList.label}';
roiLabel = 'calcarine';
% roiLabel = 'vesselCalcarine';
roiInd = ismember(roiLabelList,roiLabel);

%ts
volTs = rCond{S}.(acq).(task).volTs;
if ~isfield(volTs,'dsgn') && isfield(rCond{S}.(acq).(task),'dsgn')
    [volTs.dsgn] = deal(rCond{S}.(acq).(task).dsgn);
end
for r = 1:length(volTs)
    disp([''])
    volTs(r) = MRIload2(volTs(r));
end

%resp
forceThis   = 1;
verboseThis = 1;
for r = 1:length(volTs)
    [volResp(r), ~, info] = volTsGetResp3(do,info,volTs(r),[],volAnat,forceThis,verboseThis);
end

%mt
W = [];
K = 20;
win = inf;
% win = round(30/(volTs(1).mri.tr/1000));
verboseThis = 1;
volPsd = runFullMT3(volTs,W,K,win,[],[],volAnat.roi{roiInd}.f,[],[],[],verboseThis,[],[])';

r = 1;
plotSpecAll2(volPsd(r),volTs(r),volResp(r),volTs(r).dsgn,volAnat.roi{roiInd}.f,[],0.05)

for r = 1:length(volPsd)
    tryL2svd(volPsd(r))
    plotSpecAll2(volPsd(r),volTs(r),volResp(r),volTs(r).dsgn,volAnat.roi{roiInd}.f,[],0.05)
end

for r = 1:length(volPsd)
    plotSpecAll2(volPsd(r),volTs(r),volResp(r),volTs(r).dsgn,volAnat.roi{roiInd}.f,[],0.05)

    figure('WindowStyle','docked');
    winInd = 1;
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);
    set(gca,'YScale','log')
    grid on; grid minor
    hold on

    winInd = round(size(volPsd(r).psdTrialGramMD.t,7)/2);
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);

    winInd = size(volPsd(r).psdTrialGramMD.t,7);
    volPsd(r).psdTrialGramMD.t(:,1,1,1,1,1,winInd)
    f = squeeze(volPsd(r).psdTrialGramMD.f);
    psd = squeeze(mean(volPsd(r).psdTrialGramMD.vec.psdPC(:,:,:,:,:,:,winInd),6));
    plot(f,psd);

    legend({'early' 'mid' 'late'})
    ax = gca;
    yLim = get(ax.Children,'YData'); yLim = min(cat(1,yLim{:}),[],1); yLim = min(yLim(f>0.05)); tmp = ylim; yLim(2) = tmp(2); ylim(yLim);
end



volTs(r).mri.dsgn = volTs(r).dsgn;



plotSpecAll(volPsd(r),volTs(r).mri,volResp(r),0.05);

plotSpecAll

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%



