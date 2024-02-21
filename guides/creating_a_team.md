# Creating a Team

The access to GitHub repositories is entirely facilitated through GIAM. All user access requests are initiated and approved through GIAM. Technically, GitHub teams act only as a thin wrapper around GIAM groups, and are created implicitly on the fly when modifying repository assignments.

Note: A single team can be assigned to multiple repositories, and conversely, one repository can have multiple teams assigned. 

To create a new GitHub team and assign it to one or more repositories, follow these steps:

1. Create a new Azure security group in GIAM ([details](https://allianzms.sharepoint.com/:u:/r/teams/DE1214-6256295/SitePages/Create-Azure-Security-Group.aspx?csf=1&web=1&share=EfrPwMMX75xNsyVxYMxXFLgBapAXQHGFz9OpuVGTnT0YAw&e=QyKoaB)). The group name is flexible, allowing spaces and capitalized letters. This name will also be used to create a GitHub team with the same name. Ensure the name is unique in GIAM, and no Microsoft Teams with an identical name exist.

2. Modify the configuration file [repos.yaml](../config/repos.yaml) to include the desired assignments. You can either submit a pull request with the changes, or if you prefer, create a ticket outlining your desired modifications, and we will handle the pull request on your behalf.

After the Github Team is created, users that want to join can order the GIAM group. In such an case the bell icon in the header of GIAM will turn orange. It indicates that order must be approved by one of the owners. It's important to note that the person who created the GIAM group does not automatically become a member but must also order the group. Also, owners cannot approve their ordering request themself. Instead the second owner must approve. After approval the sync process usually takes one day, but sometimes up to 3 days to become visible in Github. Detailed instructions on joining a team can be found [here](joining_a_team.md).
