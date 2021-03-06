function [test, tFig] = EdulogClapTest(port, dur, sps, loggers)
% Perform a "Clap Test" to ensure that eduloggers are correctly measuring
% stress, by gathering data around a random noise.
%
% "port" is the port Eduloggers are connected to, this is visible on the
% Neulog API window. "dur" is the duration (s) of the clap test, it must be
% at least 15s for any response to be visible. "sps" is the number of
% samples the edulogger should take per second, up to a maximum of 5.
% "loggers" is a one dimensional cell array, with each string specifying
% the name of a different Edulogger as described in the Neulog API
% literature:
% https://neulog.com/wp-content/uploads/2014/06/NeuLog-API-version-7.pdf
%
% "test" is a structure generated by running an Edulogger experiment,
% consisting of the following fields: Time: The time (s) since the start of
% the experiment of each sample. (double) Concern: Whether or not each
% sample took more than twice the specified sample rate to retrieve
% (logical) Event (optional): Whether or not an event happened at this
% point (logical) An additional field for each kind of Edulogger used,
% containing the measurements taken at each point in data.Time. Fieldnames
% should line up with the names specified in "loggers". "tFig" is a
% Graphics Object containing the graph generated, properties of the graph
% can be changed by editing this object.

% History:
% ??-??-????    Todd Parsons    Written.

%% Essential checks
if dur < 15 % If duration is less than 15 seconds...
    error('Duration must be at least 15 seconds to allow for peaks to be visible.') % Deliver an error
end

% Play a beep sound interval seconds into the future:
interval = 5 + rand()*(dur - 10); % Calculate interval before beep to allow time for peaks to be visible
pahandle = PsychPortAudio('Open');
PsychPortAudio('FillBuffer', pahandle, repmat(MakeBeep(600, 10, 44100), 2, 1))
PsychPortAudio('Start', pahandle, 1, GetSecs + interval)

% Meanwhile, start gathering data for dur seconds, while at some point through
% the data gathering the beep sound should sound:
test = EdulogRun(port, dur, sps, loggers);

% Done. Close audio driver:
PsychPortAudio('Close');

for n = 1:dur*sps % For each sample taken
    test(n).Event = false; % Say there was no event
end

i = round(interval*sps); % Transform interval to an index
test(i).Event = true; % At the index of interval, say there was an event
tFig = EdulogPlot(test, loggers); % Plot graph
