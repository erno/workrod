# Configuration for workday automation
# Copy this to config.bash and fill in your actual values

# Workday URL for "Enter My Time" page
WORKDAY_URL='https://wd3.myworkday.com/<company>/d/task/2998$10895.htmld'

# Project configuration for time entry
# PROJECT_SEARCH: The project code or search term to type in the Time Type picker
# PROJECT_MATCH: A substring that uniquely identifies the correct project in the dropdown results
PROJECT_SEARCH='PROJ-XXXXX'
PROJECT_MATCH='Development > Project Name'
DEFAULT_COMMENT=''
