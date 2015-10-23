#!/ur/binpyton
from cobbler import api
from cobbler import utils

"""
This is a post-sync trigger
"""
def register():
    return '/var/lib/cobbler/triggers/sync/post/*'

def run(api, args, logger):
    rc = 0
    # Copy the generated PXE files - BIOS, UEFI
    pxe_cp_command_tmpl='rsync -avxSH /var/lib/tftpboot/pxelinux.cfg /var/lib/tftpboot/%s/pxelinux.cfg'
    logger.info('Copying PXE configs for BIOS')
    pxe_cp_command = pxe_cp_command_tmpl % 'bios'
    rc = utils.subprocess_call(logger, pxe_cp_command, shell=True)

    pxe_cp_command = pxe_cp_command_tmpl % 'efi64'
    logger.info('Copying PXE configs for UEFI')
    rc = utils.subprocess_call(logger, pxe_cp_command, shell=True)

    return rc
