          fileHash: 'badc0ffee',
      it('returns the fileHash for files', () => {
        expect(vm.titleLink).toBe(`#${props.diffFile.fileHash}`);
      expect(button.dataset.clipboardText).toBe('{"text":"files/ruby/popen.rb","gfm":"`files/ruby/popen.rb`"}');